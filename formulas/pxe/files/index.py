#!/usr/bin/env python

from cgi import parse_qs, escape

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

def application (environ, start_response):

    d = parse_qs(environ['QUERY_STRING'])
    uuid = d.get('uuid', [''])[0]
    uuid = escape(uuid)
    host_data = open("/var/www/html/assignments/"+uuid.upper(), "r")
    host_type = host_data.readline().strip()
    hostname_assignment = host_data.readline().strip()
    os_assignment = host_data.readline().strip()
    interface = host_data.readline().strip()

    if os_assignment == "centos7":
        response_body = body % {
            'kernel': "kernel http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/vmlinuz ks=http://{{ pxe_record }}/configs/"+host_type+" lang=en_US keymap=us ip=::::"+hostname_assignment+":"+interface+":dhcp initrd=initrd.img",
            'initrd': "initrd http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/initrd.img"
            }
    elif os_assignment == "ubuntu1804":
        response_body = body % {
            'kernel': "kernel http://us.archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux --- auto=true url=http://{{ pxe_record }}/configs/"+host_type+" locale=en_US interface="+interface+" keymap=us netcfg/get_hostname="+hostname_assignment+" netcfg/do_not_use_netplan=true debian-installer/allow_unauthenticated_ssl=true initrd=initrd.gz",
            'initrd': "initrd http://us.archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
            }
    elif os_assignment == "centos8":
        response_body = body % {
            'kernel': "kernel http://mirror.centos.org/centos/8/BaseOS/x86_64/kickstart/images/pxeboot/vmlinuz ks=http://{{ pxe_record }}/configs/"+host_type+" lang=en_US keymap=us ip=::::"+hostname_assignment+":"+interface+":dhcp initrd=initrd.img",
            'initrd': "initrd http://mirror.centos.org/centos/8/BaseOS/x86_64/kickstart/images/pxeboot/initrd.img"
            }
    elif os_assignment == "ubuntu2004":
        response_body = body % {
            'kernel': "kernel http://us.archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux --- auto=true url=http://{{ pxe_record }}/configs/"+host_type+" locale=en_US interface="+interface+" keymap=us netcfg/get_hostname="+hostname_assignment+" debian-installer/allow_unauthenticated_ssl=true initrd=initrd.gz",
            'initrd': "initrd http://us.archive.ubuntu.com/ubuntu/dists/focal/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
            }

    response_body = bytes(response_body, encoding= 'utf-8')
    status = '200 OK'
    response_headers = [
        ('Content-Type', 'text/plain'),
        ('Content-Length', str(len(response_body)))
    ]

    start_response(status, response_headers)
    return [response_body]
