# Copyright 2020 Augusta University
##
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
##
# http://www.apache.org/licenses/LICENSE-2.0
##
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

def check_all(type, needs):
    """
    Check whether or not dependencies are
    satisfied.  This function will return True
    as soon as there is a single successful check
    on any phase.  It should be used to kick off
    the orch routine.  Use chceck_one to ensure
    that individual per-phase dependencies are met.
    """
    ret = {"result": True, "type": type, "comment": []}
    for phase in needs:
        phase_ok = True
        for dep in needs[phase]:
            current_status = __salt__['mine.get'](
                tgt='role:'+dep, tgt_type='grain', fun='build_phase')
            if len(current_status) == 0:
                phase_ok = False
                ret["result"] = False
                ret["comment"].append(
                    "No endpoints of type "+dep+" available for assessment")
                break
            for endpoint in current_status:
                if current_status[endpoint] != needs[phase][dep]:
                    phase_ok = False
                    ret["result"] = False
                    ret["comment"].append(
                        endpoint+" is "+current_status[endpoint]+" but needs to be "+needs[phase][dep])
        if phase_ok is True:
            ret["comment"] = type+" orchestration routine may proceed"
            return ret
    return ret


def check_one(type, needs):
    """
    Check whether or not dependencies are
    satisfied for a specific type and phase.
    """
    ret = {"result": True, "type": type, "comment": []}
    for dep in needs:
        current_status = __salt__['mine.get'](
            tgt='role:'+dep, tgt_type='grain', fun='build_phase')
        if len(current_status) == 0:
            ret["comment"].append(
                "No endpoints of type "+dep+" available for assessment")
            ret["ready"] = False
            break
        for endpoint in current_status:
            if current_status[endpoint] != needs[dep]:
                ret["result"] = False
                ret["comment"].append(
                    endpoint+" is "+current_status[endpoint]+" but needs to be "+needs[dep])
    if ret["result"] is True:
        ret["comment"] = type+" orchestration routine may proceed"
    return ret
