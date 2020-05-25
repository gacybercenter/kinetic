#!/usr/bin/env python

from cgi import parse_qs, escape

body = """\
#!ipxe

%(kernel)s
%(initrd)s

boot || shell
"""

def application (environ, start_response):

    d = parse_qs(environ['QUERY_STRING'])
    uuid = d.get('uuid', [''])[0]
    uuid = escape(uuid)
    host_data = open("/var/www/html/assignments/"+uuid.upper(), "r")
    hostname_assignment = host_data.readline().strip()
    os_assignment = host_data.readline().strip()
    {{ interfaces }}
    if os_assignment == "centos7":
        response_body = body % {
            'kernel': "http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/vmlinuz ks=http://{{ pxe_record }}/kickstart/"+hostname_assignment.split("-")[0]+".kickstart lang=en_US keymap=us ip=::::"+hostname_assignment+":"hostname_assignment.split("-")[0]+interface+":dhcp initrd=initrd.img",
            'initrd': "http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/initrd.img"
            }

    response_body = bytes(response_body, encoding= 'utf-8')
    status = '200 OK'
    response_headers = [
        ('Content-Type', 'text/plain'),
        ('Content-Length', str(len(response_body)))
    ]

    start_response(status, response_headers)
    return [response_body]
