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

## This is a collapsed zeroize state that needs to check for two things:
## Is this state called globally?  If so, nuke everything.  If not, nuke the one thing
## Is this device physical, virtual, container, or something else?  The code path depends on this answer

## set local target variable based on pillar data.
## Set type either by calculating it based on target hostname, or use the type value itself
{% set type = pillar['type'] %}
{% set style = pillar['hosts'][type]['style'] %}
{% set targets = pillar['targets'] %}

## Follow this codepath if host is physical
{% if style == 'physical' %}

## Pull the current bmc configuration data from the pillar
  {% set api_pass = pillar['bmc_password'] %}
  {% set api_user = pillar['api_user'] %}

  {% for id in targets %}
set_bootonce_host_{{ id }}:
  salt.function:
    - name: redfish.set_bootonce
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - {{ targets[id]['api_host'] }}
      - {{ api_user }}
      - {{ api_pass }}
      - UEFI
      - Pxe

reset_host_{{ id }}:
  salt.function:
    - name: redfish.reset_host
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - {{ targets[id]['api_host'] }}
      - {{ api_user }}
      - {{ api_pass }}

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

meta_data_{{ id }}:
  salt.function:
    - name: file.write
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /srv/tftp/assignments/{{ id }}/meta-data
      - 'instance-id: {{ type }}-{{ targets[id]['uuid'] }}'
      - 'local-hostname: {{ type }}-{{ targets[id]['uuid'] }}'

user_data_{{ id }}:
  salt.function:
    - name: file.write
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /srv/tftp/assignments/{{ id }}/user-data
      - '#cloud-config'
      - 'autoinstall'
      - '  version: 1'
      - '  locale: en_US'
      - '  identity:'
      - '    hostname: {{ type }}-{{ targets[id]['uuid'] }}'
      - '    password: {{ pillar['hosts'][type]['root_password_crypted'] }}'
      - '  network:'
      - '    version: 2'
      - '    ethernets:'
      - '      {{ pillar['hosts'][type]['interface'] }}:'
      - '        dhcp4: true'
      - '  storage:'
      - '    layout:'
      - '      name: lvm'
    {% if type not in ['controller', 'controllerV2'] %}
      - '  proxy: {{ pillar['hosts'][type]['proxy'] }}'
    {% endif %}
      - '  early-commands:'
      - '    - debconf-set partman-auto/disk "$(parted_devices | grep "{{ pillar['hosts'][type]['disk'] }}" | cut -f 1 | head -n 1)"'
      - '  late-commands:'
      - '    - curl -L -o /tmp/bootstrap_salt.sh https://bootstrap.saltstack.com;'
      - '    - /bin/sh /tmp/bootstrap_salt.sh -x python3 -X -A {{ pillar['salt']['name'] }} stable {{ salt['pillar.get']('salt:version', 'latest') }}'
  {% endfor %}

## reboots initiated by the BMC take a few seconds to take effect
## This sleep ensures that the key is only removed after
## the device has actually been rebooted
{{ type }}_wheel_removal_delay:
  salt.function:
    - name: test.sleep
    - tgt: '{{ pillar['salt']['name'] }}'
    - kwarg:
        length: 5

## Follow this codepath if host is virtual
{% elif style == 'virtual' %}

wipe_{{ type }}_domains:
  salt.state:
    - tgt: 'role:controller'
    - tgt_type: grain
    - sls:
      - orch/states/virtual_zero
    - pillar:
        type: {{ type }}
    - concurrent: True

  {% for id in targets %}
prepare_vm_{{ type }}-{{ targets[id]['uuid'] }}:
  salt.state:
    - tgt: {{ targets[id]['controller'] }}
    - sls:
      - orch/states/virtual_prep
    - pillar:
        hostname: {{ type }}-{{ targets[id]['uuid'] }}
    - concurrent: true
    - require:
      - wipe_{{ type }}_domains
  {% endfor %}
{% endif %}

delete_{{ type }}_key:
  salt.wheel:
    - name: key.delete
    - match: '{{ type }}*'

expire_{{ type }}_dead_hosts:
  salt.function:
    - name: address.expire_dead_hosts
    - tgt: {{ pillar['salt']['name'] }}

## There should be some kind of retry mechanism here if this event never fires
## to deal with transient problems.  Re-exec zeroize for the given target?
wait_for_provisioning_{{ type }}:
  salt.wait_for_event:
    - name: salt/auth
    - id_list:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
{% if style == 'virtual' %}
    - timeout: 600
{% elif style == 'physical' %}
    - timeout: 1500
{% endif %}

accept_minion_{{ type }}:
  salt.wheel:
    - name: key.accept_dict
    - match:
        minions_pre:
{% for id in targets %}
          - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - require:
      - wait_for_provisioning_{{ type }}

wait_for_minion_first_start_{{ type }}:
  salt.wait_for_event:
    - name: salt/minion/*/start
    - id_list:
{% for id in targets %}
      - {{ type }}-{{ targets[id]['uuid'] }}
{% endfor %}
    - timeout: 60
    - require:
      - accept_minion_{{ type }}

{% if style == 'physical' %}
  {% for id in targets %}
remove_pending_{{ type }}-{{ id }}:
  salt.function:
    - name: file.remove
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /var/www/html/assignments/{{ id }}
    - require:
      - wait_for_minion_first_start_{{ type }}

remove_pending_dir_{{ type }}-{{ id }}:
  salt.function:
    - name: file.absent
    - tgt: '{{ pillar['pxe']['name'] }}'
    - arg:
      - /var/www/html/assignments/{{ id }}
  {% endfor %}

{% elif style == 'virtual' %}
  {% for id in targets %}
set_spawning_{{ type }}-{{ targets[id]['uuid'] }}:
  salt.function:
    - name: grains.set
    - tgt: '{{ type }}-{{ targets[id]['uuid'] }}'
    - arg:
      - spawning
    - kwarg:
          val: {{ targets[id]['spawning'] }}
    - require:
      - wait_for_minion_first_start_{{ type }}
    - retry:
        interval: 5
        attempts: 3
  {% endfor %}
{% endif %}
