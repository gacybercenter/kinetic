import ipaddress

def count_hosts(network):
	return list(ipaddress.ip_network(u'network').hosts())
