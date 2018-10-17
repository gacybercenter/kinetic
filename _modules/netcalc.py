import ipaddress

def count_hosts(network):
	addresses = list(ipaddress.ip_network('network').hosts())
	return addresses
