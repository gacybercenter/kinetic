import ipaddress

def ip_addrs(cidr=None):
    ip = list(ipaddress.ip_network(cidr).hosts())
    return [i for i in ip]

#print ip_addrs(u'192.168.0.0/24')
