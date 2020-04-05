using Recruiters
using PeaceCypher
using DemeNet: Signer, DemeSpec, Deme, ID, AbstractID, Certificate

import Base.Dict

struct MemberID <: AbstractID
    id::ID
end

Dict(id::MemberID) = Dict(id.id)
MemberID(dict::Dict) = MemberID(ID(dict))


demespec = DemeSpec("PeaceDeme",:default,:PeaceCypher,:default,:PeaceCypher,:Recruiters)
deme = Deme(demespec)

maintainer = Signer(deme,"maintainer")
server = Signer(deme,"server")

MAINTAINER_ID = maintainer.id
SERVER_ID = server.id
TOOKEN_PORT = 2006
CERTIFIER_PORT = 2007

config = CertifierConfig(MAINTAINER_ID,SERVER_ID,TOOKEN_PORT,CERTIFIER_PORT)

#certifier = Certifier{PFID}(config,deme,server)
certifier = Certifier{MemberID}(config,deme,server)

sleep(1)

tooken = 123333

addtooken(config,deme,tooken,maintainer)

# Now the maintainer shares the tooken, demespec and ledger port with new member

member = Signer(deme,"memeber")
#id = PFID("Person X","Date X",member.id)
id = MemberID(member.id)

@show cert = certify(config,deme,id,tooken)
