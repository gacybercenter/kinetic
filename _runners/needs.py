
def check_all(type, needs):
    """
    Check whether or not dependencies are
    satisfied.  This function will return True
    as soon as there is a single successful check
    on any phase.  It should be used to kick off
    the orch routine.  Use chceck_one to ensure
    that individual per-phase dependencies are met.
    """
    ret = "type"+string(needs)
    return ret

def check_one(type, phase):
    """
    Check whether or not dependencies are
    satisfied for a specific type and phase.
    """
    if str(targetString) == str(currentString):
        ret = True
    else:
        __context__["retcode"] = 1
        ret = "Got "+str(currentString)+" but looking for "+str(targetString)
    return ret
