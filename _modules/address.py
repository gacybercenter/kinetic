## module for IP address management
## interfaces with simlpe sqlite3 database in order to obviate the
## issue of dhcp relay/calculated addresses

import sqlite3

__virtualname__ = 'address'

def __virtual__():
    return __virtualname__

def login(database):
    connection = sqlite3.connect(database)
    return connection

def show_tables():
    connection = sqlite3.connect('/srv/salt/addresses.db')
    cursor = connection.cursor()
    cursor.execute('''.tables''')
    connection.close()

def create_table(table):
    login('/srv/salt/addresses.db')
    cursor = connection.cursor()
    cursor.execute('''CREATE TABLE '''+table+'''
                      (address text, host text)''')
    connection.close()
