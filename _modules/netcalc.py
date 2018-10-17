from netaddr import *

def addr(address):
    ip = IPNetwork(address)
    return list(ip)
