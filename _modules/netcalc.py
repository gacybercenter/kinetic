import salt.utils.network as network

__virtualname__ = 'netcalc'

def __virtual__():
    return __virtualname__

def gethosts(cidr):
	return network._network_hosts(cidr)


#def network_hosts(ip_addr_entry):
#    return [
#        six.text_type(host)
#        for host in ipaddress.ip_network(ip_addr_entry, strict=False).hosts()
#    ]

#def network_hosts(cidr):
#	    return [
#        six.text_type(host)
#        for host in ipaddress.ip_network(cidr, strict=False).hosts()
#    ]

#print network_hosts('192.168.200.0/24')

#def ip_addrs(cidr=None):
#    ip = list(ipaddress.ip_network(cidr).hosts())
#    return [i for i in ip]

#print ip_addrs(u'192.168.0.0/24')
