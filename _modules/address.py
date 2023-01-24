## Copyright 2020 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

## module for IP address management
## interfaces with simlpe sqlite3 database in order to obviate the
## issue of dhcp relay/calculated addresses
## includes functions focused on creating leases as well
## as functions focused on getting those leases issued to clients
## in a usable format


import json
import requests
import sqlite3
import os

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

def rest_login(username, password, url):
    login = requests.post(
                f'https://{url}:8000/login',
                verify=False,
                json={
                    'username':username,
                    'password':password,
                    'eauth':'pam'
                }
            )
    token = json.loads(login.text)["return"][0]["token"]
    return token

# NOTE(chateaulav): this function needs to be refactored to be single focused
def client_get_address(username, password, network, host, url, target):
    token = rest_login(username, password, url)
    lease = requests.post(
                f'https://{url}:8000/',
                verify=False,
                headers={
                    'X-Auth-Token':token
                },
                json=[
                    {
                    'client': 'local',
                    'tgt': target,
                    'fun': 'address.get_address',
                    'arg': [network, host]
                    }
                ]
            )
    address = json.loads(lease.text)["return"][0][target]
    return address
