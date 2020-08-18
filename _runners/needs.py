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
