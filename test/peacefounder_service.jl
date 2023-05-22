# This script starts PeaceFounder and leaves the shell open for admin
import HTTP
import Dates

import PeaceFounder: Model, Mapper, Service, Client
import .Model: TicketID, CryptoSpec, DemeSpec, Signer, id, approve

crypto = CryptoSpec("sha256", "EC: P_192")

GUARDIAN = Model.generate(Signer, crypto)
PROPOSER = Model.generate(Signer, crypto)

Mapper.initialize!(crypto)
roles = Mapper.system_roles()

demespec = DemeSpec(; 
                    uuid = Base.UUID(121432),
                    title = "A local democratic community",
                    crypto = crypto,
                    guardian = id(GUARDIAN),
                    recorder = roles.recorder,
                    recruiter = roles.recruiter,
                    braider = roles.braider,
                    proposer = id(PROPOSER),
                    collector = roles.collector
) |> approve(GUARDIAN) 

Mapper.capture!(demespec)
service = HTTP.serve!(Service.ROUTER, "0.0.0.0", 80)

#println("ROUTE: " * "http://0.0.0.0:80")
#println("HASHER: " * string(Model.hasher(demespec)))
#println("KEY: " * bytes2hex(Mapper.get_recruit_key()))

println("Copy/paste theese lines in the bash environment before starting a recruiter service:\n")

println("\texport DEME_ROUTE='http://0.0.0.0:80'")
println("\texport DEME_HASHER='$(string(Model.hasher(demespec)))'")
println("\texport DEME_RECRUIT_KEY='$(bytes2hex(Mapper.get_recruit_key()))'\n")


SERVER = Client.route("http://0.0.0.0:80")

function add_proposal()

    proposal = Model.Proposal(
        uuid = Base.UUID(2344523235),
        summary = "Should the city ban all personal automotive vehicle usage?",
        description = "We propose a groundbreaking referendum to decide whether our city should ban all personal automotive vehicle usage within its limits. This proposal aims to address the pressing issues of traffic congestion, environmental pollution, and public health, while fostering a more sustainable and livable urban environment for current and future generations. By voting in favor of this referendum, we can pave the way for transformative change, promoting alternative modes of transportation and creating a greener, healthier, and more accessible city.",
        ballot = Model.Ballot(["yes", "no"]),
        open = Dates.now() + Dates.Millisecond(100),
        closed = Dates.now() + Dates.Second(20)
    ) |> Client.configure(SERVER) |> approve(PROPOSER)

    ack = Client.enlist_proposal(SERVER, proposal)

    return ack
end


function add_braid()

    input_generator = Mapper.get_generator()
    input_members = Mapper.get_members()

    braidwork = Model.braid(input_generator, input_members, demespec, demespec, Mapper.BRAIDER[]) 

    ack = Mapper.submit_chain_record!(braidwork)

    return ack
end


function add_members()

    RECRUIT_HMAC = Model.HMAC(Mapper.get_recruit_key(), Model.hasher(demespec))

    alice_invite = Client.enlist_ticket(SERVER, Model.TicketID("Alice"), RECRUIT_HMAC) 
    bob_invite = Client.enlist_ticket(SERVER, Model.TicketID("Bob"), RECRUIT_HMAC) 
    eve_invite = Client.enlist_ticket(SERVER, Model.TicketID("Eve"), RECRUIT_HMAC) 

    alice = Client.enroll!(alice_invite; server = SERVER, key = 2)
    bob = Client.enroll!(bob_invite; server = SERVER, key = 3) 
    eve = Client.enroll!(eve_invite; server = SERVER, key = 4)

    return    
end

