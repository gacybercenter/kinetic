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

import logging


log = logging.getLogger(__name__)

__virtualname__ = "needs"

def __virtual__():
    """
    Return virtual name of the module.
    :return: The virtual name of the module.
    """
    return __virtualname__

def check_all(type, needs):
    """
    Check whether or not required services in dependencies exist,
    and then will trigger the orchestration routine.
    """
    ret = {"result": True, "type": type, "comment": []}
    log.info("****** Validating Dependencies For Service [ "+type+" ]")

    needs_list = []
    try:
        for phase in needs:
            for dep in needs[phase]:

                needs_list.append(dep)
        log.info("****** [ "+type+" ] has the following Dependencies: "+str(needs_list))

        for service in needs_list:
            current_status = __salt__['manage.up'](tgt=service+"-*")

            if len(current_status) == 0:
                log.info("****** Dependent Service [ "+service+" ] is not Available")
                __context__["retcode"] = 1
                ret["result"] = False
                ret["comment"].append("Dependent Service "+service+" is not Available")
                return ret

        if ret["result"] is True:
            __context__["retcode"] = 0
            ret["comment"] = type+" orchestration routine may proceed, all Dependent Services are Available"
            return ret

    except Exception as exc:
        log.error("Exception encountered: %s", exc)
        return False

def check_one(type, needs):
    """
    Check whether or not dependencies are
    satisfied for a specific type and phase.
    """
    ret = {"result": True, "type": type, "comment": []}
    log.info("****** Validating Dependencies For Service [ "+type+" ]")
    try:
        for dep in needs:
            current_status = __salt__['mine.get'](tgt='G@role:'+dep, tgt_type='compound', fun='build_phase')

            if len(current_status) == 0:
                log.info("****** No endpoints of type [ "+dep+" ] available for assessment")
                __context__["retcode"] = 1
                ret["comment"].append("No endpoints of type "+dep+" available for assessment")
                ret["ready"] = False
                return ret

            for endpoint in current_status:
                if current_status[endpoint] != needs[dep]:
                    log.info("****** "+endpoint+" is "+current_status[endpoint]+" but needs to be "+needs[dep])
                    __context__["retcode"] = 1
                    ret["result"] = False
                    ret["comment"].append(endpoint+" is "+current_status[endpoint]+" but needs to be "+needs[dep])
                    return ret

        if ret["result"] is True:
            __context__["retcode"] = 0
            ret["comment"] = type+" orchestration routine may proceed"
            return ret

    except Exception as exc:
        log.error("Exception encountered: %s", exc)
        return False