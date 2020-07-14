
def string(targetString, currentString):
    """
    Compare two strings and determine if they are equal,
    returning True or False as appropriate.
    This is really just a helper runner that doesn't have
    much utility beyond comparing grains, etc.
    """
    if targetString == currentString:
        ret = True
    else:
        __context__["retcode"] = 1
        result = "Got "+currentString+" but looking for "+targetString
    return ret
