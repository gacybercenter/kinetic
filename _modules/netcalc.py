import ipaddress

def count_hosts(network):
	hosts = ipaddress.ip_network(network)
	return hosts.hosts
