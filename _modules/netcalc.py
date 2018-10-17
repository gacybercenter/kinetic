def count_hosts(network):
	hosts = ipaddress.ip_network(network)
	retun hosts.hosts
