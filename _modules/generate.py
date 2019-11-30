## generate objects on-demand
import random

__virtualname__ = 'generate'

def __virtual__():
    return __virtualname__

def mac(prefix='52:54:00'):
    return '{0}:{1:02X}:{2:02X}:{3:02X}'.format(prefix,
                                                random.randint(0, 0xff),
                                                random.randint(0, 0xff),
                                                random.randint(0, 0xff))
