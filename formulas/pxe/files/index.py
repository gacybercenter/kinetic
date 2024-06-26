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

#!/usr/bin/env python

from html import escape
from os import path
from urllib.parse import parse_qs

body = """\
#!ipxe

set try:int32 0

:retry_loop iseq ${try} 4 && goto bootstrap_failure ||
## for some reason, the retcode on kernel and initrd is detected
## as a failure no matter what.  Will only retry on a failed boot
imgfree
%(kernel)s ||
%(initrd)s ||
boot || sleep 5 && inc try && echo Failed to boot on try ${try}... && goto retry_loop

:bootstrap_failure
shell
"""

def endian(val):
    little_hex = bytearray.fromhex(val)
    little_hex.reverse()
    str_little = ''.join(format(x, '02x') for x in little_hex)
    return str_little

def application (environ, start_response):

    d = parse_qs(environ['QUERY_STRING'])
    uuid = escape(d.get('uuid', [''])[0]).upper()
    print(f'recieved checking for {uuid}')

    if path.exists(f'/var/www/html/assignments/{uuid}'):
        uuid = uuid.upper()
    else:
        uuid = f'{endian(uuid[0:8])}-{endian(uuid[9:13])}-{endian(uuid[14:18])}-{uuid[19:]}'
        uuid = uuid.upper()
        print(f'swaped endianess of {uuid}')

    print(f'Validating that {uuid} directory exists')
    host_data = open(f'/var/www/html/assignments/{uuid}', "r")
    host_type = host_data.readline().strip()
    hostname_assignment = host_data.readline().strip()
    os_assignment = host_data.readline().strip()
    interface = host_data.readline().strip()

    if os_assignment == "ubuntu1804":
        response_body = body % {
            'kernel': f'kernel http://us.archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux --- auto=true url=http://{{ pxe_record }}/configs/{host_type} locale=en_US interface={interface} keymap=us netcfg/get_hostname={hostname_assignment} netcfg/do_not_use_netplan=true debian-installer/allow_unauthenticated_ssl=true initrd=initrd.gz',
            'initrd': "initrd http://us.archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
            }
    elif os_assignment == "ubuntu2004":
        response_body = body % {
            'kernel': f'kernel http://us.archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux --- auto=true url=http://{{ pxe_record }}/configs/{host_type} locale=en_US interface={interface} keymap=us netcfg/get_hostname={hostname_assignment} debian-installer/allow_unauthenticated_ssl=true initrd=initrd.gz',
            'initrd': "initrd http://us.archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
            }
    elif os_assignment == "ubuntu2204-amd64":
        response_body = body % {
            'kernel': f'kernel http://{{ pxe_record }}/tftp/jammy/amd64/vmlinuz initrd=initrd url=http://{{ pxe_record }}//tftp/jammy/ubuntu2204-amd64.iso autoinstall ip=::::{hostname_assignment}:{interface}:dhcp cloud-config-url=http://{{ pxe_record }}/tftp/assignments/{uuid.upper()}/user-data',
            'initrd': "initrd http://{{ pxe_record }}/tftp/jammy/amd64/initrd"
            }
    elif os_assignment == "ubuntu2204-arm64":
        response_body = body % {
            'kernel': f'kernel http://{{ pxe_record }}/tftp/jammy/arm64/vmlinuz initrd=initrd url=http://{{ pxe_record }}//tftp/jammy/ubuntu2204-arm64.iso autoinstall ip=::::{hostname_assignment}:{interface}:dhcp cloud-config-url=http://{{ pxe_record }}/tftp/assignments/{uuid.upper()}/user-data',
            'initrd': "initrd http://{{ pxe_record }}/tftp/jammy/arm64/initrd"
        }

    response_body = bytes(response_body, encoding= 'utf-8')
    status = '200 OK'
    response_headers = [
        ('Content-Type', 'text/plain'),
        ('Content-Length', str(len(response_body)))
    ]

    start_response(status, response_headers)
    return [response_body]
