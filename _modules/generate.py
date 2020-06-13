## generate various items on-demand.  For use in sls files when no appropriate module exists.
## inspiration for simple cephx-key function taken from
## https://github.com/ceph/ceph-ansible/blob/master/library/ceph_key.py#L26

import random, os, struct, time, base64, string

__virtualname__ = 'generate'

def __virtual__():
    return __virtualname__

def mac(prefix='52:54:00'):
    return '{0}:{1:02X}:{2:02X}:{3:02X}'.format(prefix,
                                                random.randint(0, 0xff),
                                                random.randint(0, 0xff),
                                                random.randint(0, 0xff))

def erlang_cookie(length = 20):
    return ''.join(random.choice(string.ascii_uppercase) for i in range(length))

def cephx_key():
    key = os.urandom(16)
    header = struct.pack('<hiih', 1, int(time.time()), 0, len(key))
    secret = base64.b64encode(header + key)
    return secret.decode('utf-8')
