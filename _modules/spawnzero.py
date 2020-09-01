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
