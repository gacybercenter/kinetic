## This is separated from the generate family of modules because it has a huge import requirement
## and would require python3-cryptography to be installed in too many places

from cryptography.fernet import Fernet

__virtualname__ = 'fernet'

def __virtual__():
    return __virtualname__

def make_key():
    return Fernet.generate_key().decode('utf-8')
