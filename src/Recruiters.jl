module Recruiters

using Infiltrator

import Mustache

import HTTP: Request, Response
import StructTypes
using Oxygen

import SMTPClient

import PeaceFounder: Model, Client, Mapper, Service, Parser

import .Model: HMAC, TicketID
import .Client: Invite, Route
import .Parser: marshal, unmarshal


const RECRUIT_SERVER = Ref{Route}()
const RECRUIT_HMAC = Ref{HMAC}()


struct RegistrationForm
    name::String
    email::String
end

StructTypes.StructType(::Type{RegistrationForm}) = StructTypes.Struct()
Base.:(==)(x::RegistrationForm, y::RegistrationForm) = x.name == y.name && x.email == y.email


const REGISTRATION_ROLL = Tuple{RegistrationForm, TicketID}[]

const TITLE = Ref{String}()
const PITCH = Ref{String}()

const SMTP = Ref{String}()
const EMAIL = Ref{String}()
const EMAIL_PASSWD = Ref{String}()


function get_ticketid(form::RegistrationForm)

    for (entry, ticketid) in REGISTRATION_ROLL

        if entry.email == form.email
            return ticketid
        end

    end
    
    ticketid = TicketID(rand(UInt8, 16))
    push!(REGISTRATION_ROLL, (form, ticketid))

    return ticketid
end


using Infiltrator

function send(invite::Invite, email::String)

    body = """
    From: $(EMAIL[])
    To: $email
    Subject: Invitation to $(TITLE[])
        
    Here is your invite:

    $(String(marshal(invite)))

    To use it open the PeaceFounder on your device and copy-paste this string into the form for adding the deme. The device will generate a private key, will use a token to get a recruiter signature and then finally generate a membership certificate at the current generator which can be rolled in to the braidchain. 
    
    Yours Faithfully,
    Guardian,
    $(TITLE[])
    """

    opt = SMTPClient.SendOptions(isSSL = true, username = EMAIL[], passwd = EMAIL_PASSWD[])

    SMTPClient.send(SMTP[], [email], EMAIL[], IOBuffer(body), opt)

    return
end



read_locally(fname::String) = read((@__DIR__) * "/" * fname, String)

read_html(fname::String) = Response(200, ["Content-Type" => "text/html"], read_locally(fname))
read_css(fname::String) = Response(200, ["Content-Type" => "text/css"], read_locally(fname))


function index()

    template = Mustache.load((@__DIR__) * "/index.html")
    plaintext = template(; TITLE = TITLE[], PITCH = PITCH[])

    return Response(200, ["Content-Type" => "text/html"], plaintext)
end


function register(req) 
    
    form = unmarshal(req.body, RegistrationForm)

    ticketid = get_ticketid(form)

    try

        invite = Client.enlist_ticket(RECRUIT_SERVER[], ticketid, RECRUIT_HMAC[])

        send(invite, form.email)        

        return Response(200, "Everything is ok")

    catch e
        
        @show e

        return Response(400, "Email $(form.email) is already admitted. If you have not received the invite or it's use was unsuccesful you may have become a victim of a stolen identity. To proceed you may want to ask the guardian for erasure and evaluate security of your local device and email account.")
        
    end
end


function __init__()

    @get "/" index

    @get "/css/style.css" () -> read_css("style.css")

    @post "/register" register

end


function serve(recruiter::Route, hmac::HMAC, smtp::String, email::String, email_passwd::String; title = "COMMUNITY TITLE", pitch = "PITCH FOR JOINING") 

    RECRUIT_SERVER[] = recruiter
    RECRUIT_HMAC[] = hmac

    SMTP[] = smtp
    EMAIL[] = email
    EMAIL_PASSWD[] = email_passwd

    TITLE[] = title
    PITCH[] = pitch
    
    Oxygen.serve()

    return
end


export HMAC, Route, serve

end
