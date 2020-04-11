using Recruiters
using PeaceCypher
using DemeNet: Signer, DemeSpec, Deme, ID, AbstractID, Certificate, Intent, Profile

demespec = DemeSpec("PeaceDeme",:default,:PeaceCypher,:default,:PeaceCypher,:Recruiters)
deme = Deme(demespec)

maintainer = Signer(deme,"maintainer")
server = Signer(deme,"server")

MAINTAINER_ID = maintainer.id
SERVER_ID = server.id
TOOKEN_PORT = 2006
CERTIFIER_PORT = 2007

config = CertifierConfig(MAINTAINER_ID,SERVER_ID,TOOKEN_PORT,CERTIFIER_PORT)
certifier = Certifier(config,deme,server)

sleep(1)

tooken = 123333

addtooken(config,deme,tooken,maintainer)

# Now the maintainer shares the tooken, demespec and ledger port with new member

profile = Profile(Dict("uuid"=>1234431))

member = Signer(deme,"member")
profilecert = Certificate(profile,member)

certify(CERTIFIER_PORT,SERVER_ID,deme,profilecert,tooken)

# The recruiter then can get registration 
@show take!(certifier.tookencertifier.tickets)

# ### Let's now test the ticket API

tooken = 123456

# ### The maintainer API

addtooken(config,deme,tooken,maintainer)
invite = ticket(demespec,CERTIFIER_PORT,SERVER_ID,tooken)

sleep(1)

# ### Now from users point of view
profile = Profile(Dict("uuid"=>11223344))
register(invite,profile)
@show take!(certifier.tookencertifier.tickets)

# And now lastly the sending of the ticket over email

# sendinvite(config,deme,"akels14@gmail.com",SMTPConfig(),maintainer)
