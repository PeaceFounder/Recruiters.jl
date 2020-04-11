### Could be part of PeaceVote
module Recruiters

using DemeNet: Certificate, Signer, AbstractID, Deme, Notary, Cypher, DemeSpec, Profile, AbstractID, ID, DHsym, DHasym, Intent, save
using DiffieHellman: diffiehellman
using Sockets
import DemeNet: serialize, deserialize
import Base.Dict

using SMTPClient

using Pkg.TOML

include("debug.jl")

function stack(io::IO,msg::Vector{UInt8})
    frontbytes = reinterpret(UInt8,Int16[length(msg)])
    item = UInt8[frontbytes...,msg...]
    write(io,item)
end

function unstack(io::IO)
    sizebytes = [read(io,UInt8),read(io,UInt8)]
    size = reinterpret(Int16,sizebytes)[1]
    
    msg = UInt8[]
    for i in 1:size
        push!(msg,read(io,UInt8))
    end
    return msg
end

struct Tooken
    tooken::Int
end

struct TookenID #{T<:AbstractID} <: AbstractID
    cert::Certificate{Profile}
    tooken::Tooken
end

Dict(id::TookenID) = Dict("cert"=>Dict(id.cert),"tooken"=>id.tooken.tooken)

function TookenID(dict::Dict) 
    id = Certificate{Profile}(dict["cert"])
    tooken = Tooken(dict["tooken"])
    return TookenID(id,tooken)
end

function serialize(io::IO,x::Tooken)
    bytes = reinterpret(UInt8,Int[x.tooken])
    write(io,bytes)
end

function deserialize(io::IO,::Type{Tooken})
    bytes = UInt8[]
    for i in 1:8
        byte = read(io,UInt8)
        push!(bytes,byte)
    end
    return Tooken(reinterpret(Int,bytes)[1])
end

struct CertifierConfig{T<:Any}
    tookenca::ID ### authorithies who can issue tookens. Server allows to add new tookens only from them.
    serverid::ID ### Server receiveing tookens and the member identities. Is also the one which signs and issues the certificates.
    tookenport::T
    certifierport::T
end


function validate!(tookens::Set,tooken)
    if tooken in tookens
        pop!(tookens,tooken)
        return true
    else
        return false
    end
end

### How to send back!

struct SecureRegistrator{T}
    server
    daemon
    messages::Channel{T}
end

function SecureRegistrator{T}(port,deme::Deme,validate::Function,signer::Signer) where T<:Any
    
    server = listen(port)
    messages = Channel{T}()
    
    dh = DHsym(deme,signer)

    daemon = @async while true
        socket = accept(server)
        @async begin
            
            key, id = diffiehellman(socket,dh)
            
            @assert validate(id)

            securesocket = deme.cypher.secureio(socket,key)
            message = deserialize(securesocket,T)
            put!(messages,message) 
        end
    end
    
    SecureRegistrator(server,daemon,messages)
end

struct TookenCertifier
    server
    daemon
    tookens::Set{Tooken}
    tickets::Channel{Tuple{Tooken,Certificate{Profile},Certificate{ID}}}
end

function TookenCertifier(port,deme::Deme,signer::Signer; cert=nothing, sendcopy=false) 
    tookens = Set{Tooken}()   
    tickets = Channel{Tuple{Tooken,Certificate{Profile},Certificate{ID}}}(Inf)

    server = listen(port)
    dh = DHasym(deme,signer)

    daemon = @async while true
        socket = accept(server)
        @async begin
            cert==nothing || serialize(socket,cert)
            
            key, id = diffiehellman(socket,dh)
            securesocket = deme.cypher.secureio(socket,key)

            id = deserialize(securesocket,TookenID) ### Need to implement

            @assert id.tooken in tookens
            pop!(tookens,id.tooken)

            intentid = Intent(id.cert,deme.notary)

            regid = intentid.reference

            # here one could verify that the id is indeed real
            # validate(profile,id.tooken) 

            idcert = Certificate(regid,signer)

            #tickets[id.tooken] = cert

            push!(tickets,(id.tooken,id.cert,idcert))

            # This part could be optional
            sendcopy && serialize(securesocket,cert) ### For this one we already jnow
        end
    end
    
    TookenCertifier(server,daemon,tookens,tickets)
end


struct Certifier
    tookenrecorder::SecureRegistrator{Tooken}
    tookencertifier::TookenCertifier
    daemon
end

function Certifier(config::CertifierConfig,deme::Deme,signer::Signer; cert=nothing, sendcopy=false)

    # It could be added as part of config
    # intent = Intent(config.serverid,deme.notary)
    # @assert intent.reference==deme.spec.maintainer "The certificate invalid for this deme"
    # @assert intent.document==signer.id "The provided signer does not match the certificate"
    
    tookenrecorder = SecureRegistrator{Tooken}(config.tookenport,deme,x->x in config.tookenca,signer)
    tookencertifier = TookenCertifier(config.certifierport,deme,signer; cert=cert, sendcopy=sendcopy)

    daemon = @async while true
        tooken = take!(tookenrecorder.messages)
        push!(tookencertifier.tookens,tooken)
    end

    return Certifier(tookenrecorder,tookencertifier,daemon)
end


function addtooken(cc::CertifierConfig,deme::Deme,tooken::Tooken,signer::Signer)

    socket = connect(cc.tookenport)
    
    dh = DHsym(deme,signer)

    key, id = diffiehellman(socket,dh)

    @assert id in cc.serverid

    securesocket = deme.cypher.secureio(socket,key)

    serialize(securesocket,tooken)
end

addtooken(cc::CertifierConfig,deme::Deme,tooken::Int,signer::Signer) = addtooken(cc,deme,Tooken(tooken),signer)


function certify(port,serverid::ID,deme::Deme,cert::Certificate{Profile},tooken::Tooken; sendcopy=false)
    socket = connect(port)

    dh = DHasym(deme)

    key, keyid = diffiehellman(socket,dh)

    @assert keyid in serverid

    securesocket = deme.cypher.secureio(socket,key)
    serialize(securesocket,TookenID(cert,tooken)) 

    sendcopy && (return deserialize(securesocket,Certificate{ID}))
end

certify(port,serverid::ID,deme::Deme,cert::Certificate{Profile},tooken::Int; kwargs...) = certify(port,serverid,deme,cert,Tooken(tooken); kwargs...)

function str(config::Dict)
    io = IOBuffer()
    TOML.print(io, config)
    return String(take!(io))
end

function ticket(deme::DemeSpec,port,server::ID,tooken::Int)
    config = Dict("demespec"=>Dict(deme),"port"=>Dict(port),"tooken"=>tooken,"server"=>string(server,base=16))
    return str(config)
end

function ticket(deme::DemeSpec,port::Int,server::ID,tooken::Int)
    config = Dict("demespec"=>Dict(deme),"port"=>Dict("type"=>"Int","port"=>port),"tooken"=>tooken,"server"=>string(server,base=16))
    return str(config)
end


### To use this function one is supposed to know
### How to create a identity

### I could make a function which would assume that ID type would be of a type ID. A function for Port could be passed. The problem is that we could not allow 

struct Port
    port::Int
    ip::Union{IPv4,IPv6} 
end

import Sockets.connect
connect(port::Port) = connect(port.ip,port.port)

function Dict(port::Port)
    dict = Dict()
    if port.ip isa IPv4
        dict["type"]="IPv4"
    else
        dict["type"]="IPv6"
    end
    
    dict["port"] = port.port
    dict["ip"] = string(port.ip)

    return dict
end

struct RegPort{T} end
RegPort(type::AbstractString) = RegPort{Symbol(type)}()

port(::RegPort{:IPv4},config::Dict) = Port(config["port"],IPv4(config["ip"]))
port(::RegPort{:IPv6},config::Dict) = Port(config["port"],IPv6(config["ip"]))
port(::RegPort{:Int},config::Dict) = config["port"]

function register(invite::Dict,profile::Profile; account="") where T <: AbstractID

    demespec = DemeSpec(invite["demespec"])
    save(demespec)
    deme = Deme(demespec)

    portdict = invite["port"] 
    
    @assert haskey(portdict,"type") "The type of the port must be defined"

    type = RegPort(portdict["type"])
    regport = port(type,portdict)
    
    serverid = ID(invite["server"],base=16)
    
    tooken = invite["tooken"]

    member = Signer(deme,"member")
    profilecert = Certificate(profile,member)

    certify(regport,serverid,deme,profilecert,tooken)
end


register(invite::AbstractString,profile::Profile; kwargs...) = register(TOML.parse(invite),profile; kwargs...)


struct SMTPConfig
    url::AbstractString
    email::AbstractString
    password::Union{AbstractString,Nothing}
end

function SMTPConfig()
    println("Email:")
    email = readline()

    defaulturl = "smtps://smtp.gmail.com:465" 
    println("SMTP url [$defaulturl]:")
    url = readline()
    url=="" && (url = defaulturl)
    
    println("Password:")
    password = readline()
    
    SMTPConfig(url,email,password)

end

### Need to think about this part 
### Perhaps I could add additional metadata as dictionary!

function sendinvite(config::CertifierConfig,deme::Deme,to::AbstractString,from::SMTPConfig,maintainer::Signer; init=nothing)
    ### This would register a tooken with the system 

    tooken = rand(2^62:2^63-1)
    addtooken(config,deme,tooken,maintainer)

    opt = SendOptions(isSSL = true, username = from.email, passwd = from.password)

    t = ticket(deme.spec,config.certifierport,config.serverid,tooken)

    body = """
    From: $(from.email)
    To: $to
    Subject: Invitation to $(deme.spec.name)

    ########### Ticket #############
    $t
    ################################
    """
    
    send(from.url, [to], from.email, IOBuffer(body), opt)  
end

sendinvite(config::CertifierConfig,deme::Deme,to::Vector{T},maintainer::Signer; init=nothing) where T<:AbstractString = sendinvite(config,deme,to,SMTPConfig(),maintainer; init=init)

export CertifierConfig, Certifier, addtooken, certify, ticket, register, sendinvite, SMTPConfig

end
