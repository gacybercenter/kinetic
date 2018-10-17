from netaddr import *

def addr(address):
    ip = IPNetwork(address)
    print(list(ip))
