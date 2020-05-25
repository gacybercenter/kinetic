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
    network = (network,)
    cursor.execute('SELECT address FROM addresses where host IS NULL AND network=?', network)
    address = cursor.fetchone()
    host = (host,)
    cursor.execute('UPDATE addresses SET host=?', host' WHERE address=?',address)
    connection.close()
    return address

def release_address(address):
    connection = login()
    cursor = connection.cursor()
    cursor.execute('''something''')
    connection.commit()
    connection.close()
