using Recruiters

RECRUIT_ROUTE = Recruiters.Route(ENV["DEME_ROUTE"]) 
RECRUIT_HMAC = Recruiters.HMAC(hex2bytes(ENV["DEME_RECRUIT_KEY"]), ENV["DEME_HASHER"])

SMTP = "smtps://mail.inbox.lv:465" 
EMAIL = "demerecruit@inbox.lv"

# To use environment variable do 
# export RECRUIT_EMAIL_PASSWORD='Password'
EMAIL_PASSWORD = ENV["RECRUIT_EMAIL_PASSWORD"] 

title = "Local Democratic Community"
pitch = """
<p> Are you looking for a way to get involved in local politics and make a difference in your community? Do you want to connect with like-minded individuals who share your values and beliefs? If so, we invite you to join our Local Democratic Community.</p>

<p> Our community is a group of individuals who are passionate about promoting progressive values and creating positive change in our neighborhoods and towns. We believe that by working together, we can build a more just and equitable society for everyone. As a member of our community, you will have the opportunity to attend events, participate in volunteer activities, and engage in meaningful discussions about the issues that matter most to you.</p>
"""

Recruiters.serve(RECRUIT_ROUTE, RECRUIT_HMAC, SMTP, EMAIL, EMAIL_PASSWORD; title, pitch)

