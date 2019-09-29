import os, struct, time

__virtualname__ = 'cephx'

def __virtual__():
    return __virtualname__

def make_key():
    key = os.urandom(16)
    header = struct.pack('<hiih', 1, int(time.time()), 0, len(key))
    secret = base64.b64encode(header + key)
    return secret
