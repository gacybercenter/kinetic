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

__virtualname__ = 'spawnzero'

def __virtual__():
    return __virtualname__

def check(type):
    """
    Check to see if spawn zero for a given type
    has completed and populated the mine
    """
    status = __salt__['mine.get'](tgt='G@role:'+type+' and G@spawning:0',tgt_type='compound',fun='spawnzero_complete')
    if next(iter(status.values()))['spawnzero_complete'] == True:
        ret = True
    else:
        ret = False
    return ret
