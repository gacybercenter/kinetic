## inspiration for simple salt-key module taken from
## https://github.com/ceph/ceph-ansible/blob/master/library/ceph_key.py#L26

import os, struct, time, base64

__virtualname__ = 'cephx'

def __virtual__():
    return __virtualname__

def make_key():
    key = os.urandom(16)
    header = struct.pack('<hiih', 1, int(time.time()), 0, len(key))
    secret = base64.b64encode(header + key)
    return secret.decode('utf-8')
