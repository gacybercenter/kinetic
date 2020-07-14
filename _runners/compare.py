
def string(s1, s2):
    """
    Compare two strings and determine if they are equal,
    returning True or False as appropriate.
    This is really just a helper runner that doesn't have
    much utility beyond comparing grains, etc.
    """
    if s1 == s2:
        result = True
    else:
        __context__["retcode"] = 1
        result = False
    return result
