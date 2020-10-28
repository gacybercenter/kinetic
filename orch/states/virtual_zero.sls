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

{% set type = pillar['type'] %}


## This can be further improved - see https://docs.saltstack.com/en/master/ref/modules/all/salt.modules.virt.html#salt.modules.virt.vm_info
## and https://libvirt.org/formatdomain.html#elementsMetadata
## we can define custom metadata which is then checked before taking action on a domain (e.g. we set roles/types rather than calcualting them)
{% for domain in salt['virt.list_domains']() if type == domain.split('-')[0] %}
stop_{{ domain }}:
  virt.powered_off:
    - name: {{ domain }}
    - require_in:
      - remove_{{ domain }}
      - remove_{{ domain }}_logs
      - report_success
{% endfor %}

{% for domain in salt['file.readdir']('/kvm/vms') if type == domain.split('-')[0] %}
remove_{{ domain }}:
  file.absent:
    - name: /kvm/vms/{{ domain }}
    - require_in:
      - report_success

remove_{{ domain }}_logs:
  file.absent:
    - name: /var/log/libvirt/{{ domain }}.log
    - require_in:
      - report_success
{% endfor %}

report_success:
  test.nop
