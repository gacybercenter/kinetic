#!/usr/bin/env python3
# Implements: 800-171 3.1.21 3.8.7
# Pin Guacamole connection USB/drive/SFTP/printing off.
# Empty defaults are not a pin.

import argparse
import sys

import mysql.connector

HOST = "{{ mysql_host }}"
DB = "{{ mysql_db }}"
USER = "{{ mysql_user }}"
PASSWORD = "{{ mysql_password }}"

PINS = (
    ("enable-drive", "false"),
    ("create-drive-path", "false"),
    ("enable-sftp", "false"),
    ("enable-printing", "false"),
)

UPSERT = """
INSERT INTO guacamole_connection_parameter
    (connection_id, parameter_name, parameter_value)
SELECT c.connection_id, %s, %s
FROM guacamole_connection c
ON DUPLICATE KEY UPDATE parameter_value = VALUES(parameter_value)
"""

CHECK = """
SELECT COUNT(*) FROM guacamole_connection c
WHERE EXISTS (
    SELECT 1 FROM guacamole_connection_parameter p
    WHERE p.connection_id = c.connection_id
      AND p.parameter_name = %s
      AND p.parameter_value = %s
)
"""


def connect():
    return mysql.connector.connect(
        host=HOST, database=DB, user=USER, password=PASSWORD
    )


def pinned(cur):
    cur.execute("SELECT COUNT(*) FROM guacamole_connection")
    total = cur.fetchone()[0]
    if total == 0:
        return True
    for name, value in PINS:
        cur.execute(CHECK, (name, value))
        if cur.fetchone()[0] != total:
            return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    conn = connect()
    cur = conn.cursor()
    if args.check:
        ok = pinned(cur)
        cur.close()
        conn.close()
        sys.exit(0 if ok else 1)
    for name, value in PINS:
        cur.execute(UPSERT, (name, value))
    conn.commit()
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
