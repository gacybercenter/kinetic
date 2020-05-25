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

def show_tables():
    connection = login()
    cursor = connection.cursor()
    cursor.execute('''SHOW TABLES''')
    connection.close()

def create_table(table):
    connection = login()
    cursor = connection.cursor()
    cursor.execute('''CREATE TABLE '''+table+'''
                      (address text, host text)''')
    connection.close()

def drop_table(table):
    connection = login()
    cursor = connection.cursor()
    cursor.execute('''DROP TABLE '''+table)
    connection.close()
