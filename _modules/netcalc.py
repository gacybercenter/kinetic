from netaddr import *

def addr(address, prefix):
    ip = IPNetwork(address)
    ip.prefixlen = int(prefix)
    return ip
