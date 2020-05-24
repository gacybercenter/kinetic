#!/usr/bin/env python

from cgi import parse_qs, escape

body = """
#!ipxe

kernel %(kernel)s
initrd %(initrd)s
boot ||
echo net boot failed, booting ipxe shell
shell
"""

def application (environ, start_response):

    d = parse_qs(environ['QUERY_STRING'])
    uuid = d.get('uuid', [''])[0]
    uuid = escape(uuid)
    os_assignment = open("assignments/"+uuid, "r")
    response_body = body % {
        'kernel': CentOS,
        'initrd':Ubuntu                                                                                 
        }
    response_body = bytes(response_body, encoding= 'utf-8')
    status = '200 OK'
    response_headers = [
        ('Content-Type', 'text/plain'),
        ('Content-Length', str(len(response_body)))
    ]

    start_response(status, response_headers)
    return [response_body]
