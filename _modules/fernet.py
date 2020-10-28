## Copyright 2020 Augusta University
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

## This is separated from the generate family of modules because it has a huge import requirement
## and would require python3-cryptography to be installed in too many places

from cryptography.fernet import Fernet

__virtualname__ = 'fernet'

def __virtual__():
    return __virtualname__

def make_key():
    return Fernet.generate_key().decode('utf-8')
