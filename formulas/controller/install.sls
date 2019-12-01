qemu-kvm:
  pkg.installed

genisoimage:
  pkg.installed

mdadm:
  pkg.installed:
    - reload_modules: True

xfsprogs:
  pkg.installed

bridge-utils:
  pkg.installed

haveged:
  pkg.installed

{% if grains['os_family'] == 'Debian' %}
python3-libvirt:
  pkg.installed

libvirt-clients:
  pkg.installed

libvirt-daemon-system:
  pkg.installed

qemu-utils:
  pkg.installed

{% elif grains['os_family'] == 'RedHat' %}

libvirt-python:
  pkg.installed

libvirt-client:
  pkg.installed

libvirt-daemon-kvm:
  pkg.installed
{% endif %}
