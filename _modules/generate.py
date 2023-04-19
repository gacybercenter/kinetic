## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

## generate various items on-demand.  For use in sls files when no appropriate module exists.
## inspiration for simple cephx-key function taken from
## https://github.com/ceph/ceph-ansible/blob/master/library/ceph_key.py#L26

import base64
import os
import random
import string
import struct
import time

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

