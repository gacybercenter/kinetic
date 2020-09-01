## module for IP address management
## interfaces with simlpe sqlite3 database in order to obviate the
## issue of dhcp relay/calculated addresses
## includes functions focused on creating leases as well
## as functions focused on getting those leases issued to clients
## in a usable format

import sqlite3, requests, json, os

__virtualname__ = 'address'

def __virtual__():
    return __virtualname__

def login(database = '/srv/addresses/addresses.db'):
    connection = sqlite3.connect(database)
    return connection

def get_address(network, host):
    connection = login()
    cursor = connection.cursor()
    q = (host, network)
    cursor.execute('SELECT address FROM addresses where host=? AND network=?', q)
    existing_lease = cursor.fetchone()
    if existing_lease is None:
        n = (network, )
        cursor.execute('SELECT address FROM addresses where host IS NULL AND network=?', n)
        address = cursor.fetchone()[0]
        d = (host, address)
        cursor.execute("UPDATE addresses SET host=? WHERE address=?", d)
        connection.commit()
        connection.close()
        return address
    else:
        return existing_lease[0]

def release_single_address(address):
    connection = login()
    cursor = connection.cursor()
    a = (address, )
    cursor.execute("UPDATE addresses SET host=NULL WHERE address=?", a)
    connection.commit()
    connection.close()

def expire_dead_hosts():
    connection = login()
    cursor = connection.cursor()
    cursor.execute("SELECT host FROM addresses WHERE host IS NOT NULL")
    all_leases = cursor.fetchall()
    working_list = all_leases
    minions = os.listdir('/etc/salt/pki/master/minions')
    for minion in minions:
        m = (minion, )
        cursor.execute("SELECT host FROM addresses WHERE host=?", m)
        minion_leases = cursor.fetchall()
        working_list = [i for i in working_list if i not in minion_leases]
    working_list = list(set(working_list))
    for host in working_list:
        release_all_host_addresses(str(host[0]))
    cursor.execute("SELECT host FROM addresses WHERE host IS NOT NULL")
    remaining_leases = cursor.fetchall()
    connection.commit()
    connection.close()
    return remaining_leases

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

def rest_login(username, password):
    login = requests.post('https://salt:8000/login', verify=False, json={'username':'api',
                                                                         'password':''+password+'',
                                                                         'eauth':'pam'})
    token = json.loads(login.text)["return"][0]["token"]
    return token

def client_get_address(username, password, network, host):
    token = rest_login(username, password)
    lease = requests.post('https://salt:8000/', verify=False, headers={'X-Auth-Token':token}, json=[{
    'client': 'local',
    'tgt': 'salt',
    'fun': 'address.get_address',
    'arg': [network, host]
    }])
    address = json.loads(lease.text)["return"][0]["salt"]
    return address
