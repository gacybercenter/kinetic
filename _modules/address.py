## module for IP address management
## interfaces with simlpe sqlite3 database in order to obviate the
## issue of dhcp relay/calculated addresses

import sqlite3

__virtualname__ = 'address'

def __virtual__():
    return __virtualname__

def login(database = '/srv/salt/addresses.db'):
    connection = sqlite3.connect(database)
    return connection

def get_address(network, host):
    connection = login()
    cursor = connection.cursor()
    n = (network,)
    cursor.execute('SELECT address FROM addresses where host IS NULL AND network=?', n)
    address = cursor.fetchone()[0]
    d = (host, address)
    cursor.execute("UPDATE addresses SET host=? WHERE address=?", d)
    connection.commit()
    connection.close()
    return address

def release_single_address(address):
    connection = login()
    cursor = connection.cursor()
    a = (address, )
    cursor.execute("UPDATE addresses SET host=NULL WHERE address=?", a)
    connection.commit()
    connection.close()

def release_all_host_addresses(host):
    connection = login()
    cursor = connection.cursor()
    h = (host, )
    cursor.execute("UPDATE addresses SET host=NULL WHERE host=?", h)
    connection.commit()
    connection.close()

def release_all_addresses():
    connection = login()
    cursor = connection.cursor()
    cursor.execute("UPDATE addresses SET host=NULL")
    connection.commit()
    connection.close()
