import ipaddress

def count_hosts(network):
	addresses = list(ipaddress.ip_network(u'network').hosts())
	return addresses
