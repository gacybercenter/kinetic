controller_packages:
  pkg.installed:
    - pkgs:
      - qemu-kvm
      - genisoimage
      - mdadm
      - xfsprogs
      - bridge-utils
      - haveged
    - reload_modules: true

{% if grains['os_family'] == 'Debian' %}

controller_packages_deb:
  pkg.installed:
    - pkgs:
      - python3-libvirt
      - libvirt-clients
      - libvirt-daemon-system
      - qemu-utils
    - reload_modules: true

{% elif grains['os_family'] == 'RedHat' %}

controller_packages_rpm:
  pkg.installed:
    - pkgs:
      - libvirt-python
      - libvirt-client
      - libvirt-daemon-kvm
    - reload_modules: true          

{% endif %}
