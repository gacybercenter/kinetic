import salt.utils.network as network

__virtualname__ = 'netcalc'

def __virtual__():
    return __virtualname__

def gethosts(cidr):
	return network._network_hosts(cidr)
