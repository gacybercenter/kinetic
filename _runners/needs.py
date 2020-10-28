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

def check_all(type, needs):
    """
    Check whether or not dependencies are
    satisfied.  This function will return True
    as soon as there is a single successful check
    on any phase.  It should be used to kick off
    the orch routine.  Use chceck_one to ensure
    that individual per-phase dependencies are met.
    """
    ret = {"ready": True, "type": type, "comment": []}
    for phase in needs:
      phaseOK = True
      for dep in needs[phase]:
        currentStatus = __salt__['mine.get'](tgt='role:'+dep,tgt_type='grain',fun='build_phase')
        if len(currentStatus) == 0:
          __context__["retcode"] = 1
          phaseOK = False
          ret["ready"] = False
          ret["comment"].append("No endpoints of type "+dep+" available for assessment")
          break
        for endpoint in currentStatus:
          if currentStatus[endpoint] != needs[phase][dep]:
            __context__["retcode"] = 1
            phaseOK = False
            ret["ready"] = False
            ret["comment"].append(endpoint+" is "+currentStatus[endpoint]+" but needs to be "+needs[phase][dep])
      if phaseOK == True:
        __context__["retcode"] = 0          
        ret["ready"] = True
        ret["comment"] = type+" orchestration routine may proceed"
        return ret
    return ret

def check_one(type, needs):
    """
    Check whether or not dependencies are
    satisfied for a specific type and phase.
    """
    ret = {"ready": True, "type": type, "comment": []}
    for dep in needs:
      currentStatus = __salt__['mine.get'](tgt='role:'+dep,tgt_type='grain',fun='build_phase')
      if len(currentStatus) == 0:
        __context__["retcode"] = 1
        ret["comment"].append("No endpoints of type "+dep+" available for assessment")
        ret["ready"] = False
        break
      for endpoint in currentStatus:
        if currentStatus[endpoint] != needs[dep]:
          __context__["retcode"] = 1
          ret["ready"] = False
          ret["comment"].append(endpoint+" is "+currentStatus[endpoint]+" but needs to be "+needs[dep])
    if ret["ready"] == True:
      ret["comment"] = type+" orchestration routine may proceed"
    return ret
