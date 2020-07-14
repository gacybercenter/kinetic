
def phase(targetPhase, currentPhase):
    """
    Compare two strings and determine if they are equal,
    returning True or False as appropriate.
    This is really just a helper runner that doesn't have
    much utility beyond comparing grains, etc.
    """
    if targetPhase == currentPhase:
        result = True
    else:
        __context__["retcode"] = 1
        result = "Got "+currentPhase+" but looking for "+targetPhase
    return result
