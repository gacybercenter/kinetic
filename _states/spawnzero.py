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

def check(name, type, value, **kwargs):
    """
    Check if spawnzero is complete by targeting spawning:0 of the specified role type,
    this pulls directly from mine data
    """

    ret = {"name": name, "result": False, "changes": {}, "comment": ""}

    expected = value

    if "test" not in kwargs:
        kwargs["test"] = __opts__.get("test", False)

    status = __salt__['mine.get'](tgt='G@role:'+type+' and G@spawning:0',tgt_type='compound',fun='spawnzero_complete')
    current = next(iter(status.values()))

    if kwargs["test"]:
        if current == expected:
            ret["comment"] = "Spawnzero Check would be complete"
            ret["result"] = None
        else:
            ret["changes"] = {
                "old": current,
                "new": expected,
            }
            ret["comment"] = "Spawnzero Check would not be complete"
            ret["result"] = None
        return ret

    if current == expected:
        ret["result"] = True
        ret["comment"] = "Spawnzero Check Successful"
        return ret

    ret["changes"] = {
        "old": current,
        "new": expected,
    }
    ret["comment"] = "Spawnzero Check not complete"
    return ret