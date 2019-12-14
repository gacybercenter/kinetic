## generate various items on-demand.  For use in sls files when no appropriate module exists.
import random
import string

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
