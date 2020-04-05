### Could be part of PeaceVote
module Recruiters

using DemeNet: Certificate, Signer, AbstractID, Deme, Notary, Cypher, DemeSpec, Profile, AbstractID, ID, DHsym, DHasym
using DiffieHellman: diffiehellman
using Sockets
import DemeNet: serialize, deserialize
import Base.Dict

using SMTPClient


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

struct TookenID{T<:AbstractID} <: AbstractID
    id::T
    tooken::Tooken
end

Dict(id::TookenID) = Dict("id"=>Dict(id.id),"tooken"=>id.tooken.tooken)

function TookenID{T}(dict::Dict) where T <: AbstractID
    id = T(dict["id"])
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
    #hmac for keeping the tooken secret
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

struct TookenCertifier{T}
    server
    daemon
    tookens::Set{Tooken}
    tickets::Dict{Tooken,Certificate{T}}
end

function TookenCertifier{T}(port,deme::Deme,signer::Signer) where T<:AbstractID
    tookens = Set{Tooken}()   
    tickets = Dict{Tooken,Certificate{T}}()

    server = listen(port)
    dh = DHasym(deme,signer)

    daemon = @async while true
        socket = accept(server)
        @async begin
            
            key, id = diffiehellman(socket,dh)
            securesocket = deme.cypher.secureio(socket,key)

            id = deserialize(securesocket,TookenID{T}) ### Need to implement

            @assert id.tooken in tookens
            pop!(tookens,id.tooken)

            cert = Certificate(id.id,signer)

            tickets[id.tooken] = cert
            
            serialize(securesocket,cert) ### For this one we already jnow
        end
    end
    
    TookenCertifier(server,daemon,tookens,tickets)
end


struct Certifier{T<:AbstractID} 
    tookenrecorder::SecureRegistrator{Tooken}
    tookencertifier::TookenCertifier{T}
    daemon
end

function Certifier{T}(config::CertifierConfig,deme::Deme,signer::Signer) where T<:AbstractID
    
    tookenrecorder = SecureRegistrator{Tooken}(config.tookenport,deme,x->x in config.tookenca,signer)
    tookencertifier = TookenCertifier{T}(config.certifierport,deme,signer)

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


function certify(cc::CertifierConfig,deme::Deme,id::T,tooken::Tooken) where T <: AbstractID

    socket = connect(cc.certifierport)

    dh = DHasym(deme)

    key, keyid = diffiehellman(socket,dh)

    @assert keyid in cc.serverid

    securesocket = deme.cypher.secureio(socket,key)
    serialize(securesocket,TookenID(id,tooken)) 
    
    cert = deserialize(securesocket,Certificate{T})

    return cert
end

certify(cc::CertifierConfig,deme::Deme,id::T,tooken::Int) where T <: AbstractID = certify(cc,deme,id,Tooken(tooken))


function ticket(deme::DemeSpec,port,tooken::Int)
    config = Dict("demespec"=>Dict(deme),"port"=>Dict(port),"tooken"=>tooken)
    io = IOBuffer()
    TOML.print(io, config)
    return String(take!(io))
end

### To use this function one is supposed to know
### How to create a identity

function register(invite::Dict,profile::Profile; account="")

    demespec = DemeSpec(invite["demespec"])
    save(demespec)

    deme = Deme(demespec)
    if haskey(invite,"port")
        sync!(deme,invite["port"]) 
    end

    tooken = invite["tooken"]
    #keychain = KeyChain(deme,account)
    member = Signer(deme,"member")
    id = member.id

    
    register(deme,profile,id,tooken)
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
### Perhaps I could add additional metadata as dictionary

function sendinvite(config::CertifierConfig,deme::Deme,to::AbstractString,from::SMTPConfig,maintainer::Signer; init=nothing)
    ### This would register a tooken with the system 

    tooken = rand(2^62:2^63-1)
    Recruiters.addtooken(config.certifier,deme,tooken,maintainer)

    port = config.syncport
    
    opt = SendOptions(isSSL = true, username = from.email, passwd = from.password)

    t = ticket(deme.spec,port,tooken)

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


# function sendinvite(deme::Deme,to::Vector{T},smtpconfig::SMTPConfig,maintainer::Signer) where T<:AbstractString
#     config = deserialize(deme,SystemConfig)
#     for ito in to
#         sendinvite(config,deme,ito,smtpconfig,maintainer)
#     end
# end


sendinvite(config::CertifierConfig,deme::Deme,to::Vector{T},maintainer::Signer; init=nothing) where T<:AbstractString = sendinvite(config,deme,to,SMTPConfig(),maintainer; init=init)



export addtooken, Certifier, certify, CertifierConfig

end
