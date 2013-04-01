from hashlib import sha1
import hmac
import binascii
print binascii.b2a_base64(hmac.new('jUDB7ZWqQZFxkkeSwcGp5vNrBw36usENEESKGpXM','AWSMechanicalTurkRequesterGetReviewableHITs2013-04-01T05:29:21Z', sha1).digest())[:-1]
print binascii.b2a_base64(hmac.new('jUDB7ZWqQZFxkkeSwcGp5vNrBw36usENEESKGpXM','AWSMechanicalTurkRequesterGetAssignmentsForHIT2013-04-01T05:29:21Z', sha1).digest())[:-1]
