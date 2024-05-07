## Copyright 2019 Augusta University
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

{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set targets = pillar['targets'] %}

{% if style == 'physical' %}

## Pull the current bmc configuration data from the pillar
  {% set api_pass = pillar['bmc_password'] %}
  {% set api_user = pillar['api_user'] %}

  {% for id in targets %}
assign_uuid_to_{{ id }}:
  salt.function:
    - name: file.write
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /var/www/html/assignments/{{ id }}
      - {{ type }}
      - {{ type }}-{{ targets[id]['uuid'] }}
      - {{ pillar['hosts'][type]['os'] }}
      - {{ pillar['hosts'][type]['interface'] }}
      - {{ targets[id]['api_host'] }}

assignments_dir_{{ id }}:
  salt.function:
    - name: cmd.run
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - 'mkdir -p /srv/tftp/assignments/{{ id }}'

meta_data_{{ id }}:
  salt.function:
    - name: file.write
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /srv/tftp/assignments/{{ id }}/meta-data
      - 'instance-id: {{ type }}-{{ targets[id]['uuid'] }}'
      - 'local-hostname: {{ type }}-{{ targets[id]['uuid'] }}'
    - require:
      - assignments_dir_{{ id }}


## NOTE(chateaulav): This generates the required user-data file for
##                   cloud-init autoinstall, which targets provisioning
##                   a plain baremetal server allowing for further
##                   configuration via saltstack.  For the storage layout,
##                   ensure you run the command:
##                   'udevadm info /dev/<DISK NAME> | grep ID_MODEL'
##                   and use the output as the value for the 'model' key in
##                   the 'match' section of the storage layout.
user_data_{{ id }}:
  salt.function:
    - name: file.write
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /srv/tftp/assignments/{{ id }}/user-data
      - '#cloud-config'
      - 'autoinstall:'
      - '  version: 1'
      - '  refresh-installer:'
      - '    update: yes'
      - '  early-commands:'
      - "    - |"
      - "      vgs --separator=: --noheadings | cut -f1 -d: | while read vg ; do vgchange -an $vg ; done"
      - "      pvs --separator=: --noheadings | cut -f1 -d: | while read pv ; do pvremove -ff -y $pv ; done"
      - "      fdisk -l | grep 'Disk /dev/sd' | cut -f1 -d: | cut -f2 -d' ' | while read disk ; do mdadm --zero-superblock $disk ; done"
      - "      fdisk -l | grep 'Disk /dev/nvme' | cut -f1 -d: | cut -f2 -d' ' | while read disk ; do mdadm --zero-superblock $disk ; done"
      - "      fdisk -l | grep 'Disk /dev/sd' | cut -f1 -d: | cut -f2 -d' ' | while read disk ; do dd if=/dev/zero of=$disk bs=1M count=512 ; done"
      - "      fdisk -l | grep 'Disk /dev/nvme' | cut -f1 -d: | cut -f2 -d' ' | while read disk ; do dd if=/dev/zero of=$disk bs=1M count=512 ; done"
      - '  locale: en_US'
      - '  identity:'
      - '    username: gacyberrange'
      - '    hostname: {{ type }}-{{ targets[id]['uuid'] }}'
      - '    password: "{{ pillar['hosts'][type]['root_password_crypted'] }}"'
      - '  network:'
      - '    version: 2'
      - '    ethernets:'
      - '      {{ pillar['hosts'][type]['interface'] }}:'
      - '        dhcp4: true'
      - '  resize_rootfs: true'
      - '  growpart:'
      - '    mode: auto'
      - '  storage:'
      - '    layout:'
      - '      name: lvm'
      - '      sizing-policy: all'
      - '      match:'
      - '        model: "{{ pillar['hosts'][type]['disk'] }}"'
      - '  user-data:'
      - '    disable_root: false'
      - '    runcmd:'
      - '      - curl -L -o /tmp/bootstrap_salt.sh https://bootstrap.saltstack.com'
      - '      - /bin/sh /tmp/bootstrap_salt.sh -x python3 -X -A {{ pillar['salt']['record'] }} stable {{ salt['pillar.get']('salt:version', 'latest') }}'
      - '  late-commands:'
      - '    - |'
      - '      hostnamectl set-hostname {{ type }}-{{ targets[id]['uuid'] }}'
      - '      echo {{ type }}-{{ targets[id]['uuid'] }} > /etc/hostname'
      - "      sed -i 's/ubuntu-server/{{ type }}-{{ targets[id]['uuid'] }}/g' /etc/hosts"
    - require:
      - assignments_dir_{{ id }}
  {% endfor %}
{% endif %}