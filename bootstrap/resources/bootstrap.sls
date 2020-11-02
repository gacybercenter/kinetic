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

bootstrap_packages:
  pkg.installed:
    - pkgs:
      - qemu-kvm
      - genisoimage
      - python3-libvirt
      - libguestfs-tools
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% if grains['os_family'] == 'Debian' %}

bootstrap_packages_deb:
  pkg.installed:
    - pkgs:
      - libvirt-clients
      - libvirt-daemon-system
      - qemu-utils
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% elif grains['os_family'] == 'RedHat' %}

bootstrap_packages_rpm:
  pkg.installed:
    - pkgs:
      - libvirt-client
      - libvirt-daemon-kvm
    - reload_modules: true
    - onchanges_in:
      - pkg: update_packages_bootstrap
    - onchanges_in:
      - pkg: update_packages_bootstrap

{% endif %}

update_packages_bootstrap:
  pkg.uptodate:
    - refresh: rue
    - dist_upgrade: True

/kvm/images:
  file.directory:
    - makedirs: True

/kvm/vms:
  file.directory:
    - makedirs: True

## <hack> the kmod state doesn't correctly parse arguments like the kmod module
## does. Shoule open a PR to fix it, but this works for now
/etc/modules-load.d/nested_kvm.conf:
  file.managed:
    - contents: |
{% if "AMD" in grains['cpu_model'] %}
        kvm_amd nested=1
{% elif "Intel" in grains['cpu_model'] %}
        kvm_intel nested=1
{% endif %}

load_kvm:
  cmd.run:
{% if "AMD" in grains['cpu_model'] %}
    - name: rmmod kvm_amd ; modprobe kvm_amd nested=1
{% elif "Intel" in grains['cpu_model'] %}
    - name: rmmod kvm_intel ; modprobe kvm_intel nested=1
{% endif %}
    - onchanges:
      - file: /etc/modules-load.d/nested_kvm.conf
## </hack>

## images
debian_base_image:
  file.managed:
    - name: /kvm/images/debian10.raw
    - source: https://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.raw
    - source_hash: https://cdimage.debian.org/cdimage/openstack/current-10/SHA512SUMS

{% for hostname in ['salt, pxe'] %}
/kvm/vms/{{ hostname }}/config.xml:
  file.managed:
    - source: salt://bootstrap/resources/common.xml
    - makedirs: True
    - template: jinja
    - defaults:
        name: {{ host }}
        ram: {{ pillar[hostname]['conf']['ram'] }}
        cpu: {{ pillar[hostname]['conf']['cpu'] }}
        interface: {{ pillar[hostname]['conf']['interface'] }}

/kvm/vms/{{ hostname }}/disk0.raw:
  file.copy:
    - source: /kvm/images/debian10.raw

qemu-img resize -f raw /kvm/vms/{{ hostname }}/disk0.raw {{ pillar[hostname]['conf']['disk'] }}:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/disk0.raw

/kvm/vms/{{ hostname }}/data/meta-data:
  file.managed:
    - source: salt://formulas/bootstrap/resources/common.metadata
    - makedirs: True
    - template: jinja
    - defaults:
        hostname: {{ hostname }}

/kvm/vms/{{ hostname }}/data/user-data:
  file.managed:
    - source: salt://formulas/bootstrap/resources/common.userdata
    - makedirs: True
    - template: jinja
    - defaults:
{% for key, encoding in pillar['authorized_keys'].items() if loop.index0 == 0 %}
        key: {{ key }}
{% endfor %}
{% if hostname = 'pxe' %}
        opts: -X -x python3 -i pxe
        extra_commands: echo no extra commands specified
{% elif hostname = 'salt' %}
        opts: -M -x python3 -X -i salt -J \'{ \"default_top\": \"base\", \"fileserver_backend\": [ \"git\" ], \"ext_pillar\": [ { \"git\": [ { \"$pillar_branch $pillar\": [ { \"env\": \"base\" } ] } ] } ], \"ext_pillar_first\": true, \"gitfs_remotes\": [ { \"$fileroot\": [ { \"saltenv\": [ { \"base\": [ { \"ref\": \"$fileroot_branch\" } ] } ] } ] } ], \"gitfs_saltenv_whitelist\": [ \"base\" ] }\'
        extra_commands: mkdir -p /etc/salt/gpgkeys;chmod 0700 /etc/salt/gpgkeys;curl -s https://raw.githubusercontent.com/GeorgiaCyber/kinetic/master/bootstrap/resources/key-generation | gpg --expert --full-gen-key --homedir /etc/salt/gpgkeys/ --batch;gpg --export --homedir /etc/salt/gpgkeys -a > /root/key.gpg"
{% endif %}

genisoimage -o /kvm/vms/{{ hostname }}/config.iso -V cidata -r -J /kvm/vms/{{ hostname }}/data/meta-data /kvm/vms/{{ hostname }}/data/user-data:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/data/meta-data
      - /kvm/vms/{{ hostname }}/data/user-data

virsh create /kvm/vms/{{ hostname }}/config.xml:
  cmd.run:
    - onchanges:
      - /kvm/vms/{{ hostname }}/config.xml
