## Copyright 2018 Augusta University
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

{% set type = opts.id.split('-')[0] %}
{% set role = salt['pillar.get']('hosts:'+type+':role', type) %}

include:
  - /formulas/common/fluentd/repo

initial_module_sync:
  saltutil.sync_all:
    - refresh: True
    - unless:
      - fun: grains.has_value
        key: build_phase

build_phase:
  grains.present:
    - value: base
    - unless:
      - fun: grains.has_value
        key: build_phase

type:
  grains.present:
    - value: {{ type }}

role:
  grains.present:
    - value: {{ role }}

{{ pillar['timezone'] }}:
  timezone.system:
    - utc: True

python3_pip:
  pkg.installed:
    - pkgs:
      - python3-pip
    - reload_modules: True

# Allow for minion result checkin randomization
/etc/salt/minion.d/98-tunning.conf:
  file.managed:
    - source: salt://formulas/common/minion/98-tunning.conf

{% if grains['os_family'] == 'Debian' %}
/etc/systemd/timesyncd.conf:
  file.managed:
    - source: salt://formulas/common/ntp/timesyncd.conf
    - template: jinja
    - defaults:
        ntp_server: {{ pillar['ntp']['ntp_server'] }}
        ntp_fallback: {{ pillar['ntp']['ntp_fallback'] }}
  cmd.wait:
    - name: timedatectl set-ntp true

/etc/sysctl.conf:
  file.managed:
    - source: salt://formulas/common/sysctl/files/sysctl.conf

sysctl -p:
  cmd.run:
    - require:
      - file: /etc/sysctl.conf
    - unless:
      - sysctl -n 'net.core.netdev_max_backlog' | grep -q 10000
{% endif %}

{% for key in pillar['authorized_keys'] %}
{{ key }}:
  ssh_auth.present:
    - user: root
    - enc: {{ pillar['authorized_keys'][ key ]['encoding'] }}
{% endfor %}

{% if opts.id not in ['salt', 'pxe'] %}
hosts_name_resolution:
  host.present:
    - ip: {{ salt['network.ipaddrs'](cidr=pillar['networking']['subnets']['management'])[0] }}
    - names:
      - {{ grains['id'] }}
      - {{ grains['host'] }}
    - clean: true
{% endif %}

/etc/rsyslog.d/10-syslog.conf:
  file.managed:
    - source: salt://formulas/common/syslog/files/10-syslog.conf
    - template: jinja
    - defaults:
        logger: 127.0.0.1:5514


{% if grains['os_family'] == 'Debian' %}
timesyncd:
  service.running:
    - name: systemd-timesyncd
    - enable: True
    - onchanges:
      - /etc/systemd/timesyncd.conf
{% endif %}

rsyslog:
  service.running:
    - watch:
      - /etc/rsyslog.d/10-syslog.conf

/etc/security/limits.d/90-ulimit-default.conf:
  file.managed:
    - source: salt://formulas/common/ulimit/90-ulimit-default.conf
    - user: root
    - group: root
    - mode: "0644"

{% if role == 'gpu' %}
/etc/modprobe.d/blacklist-nouveau.conf:
  file.managed:
    - source: salt://formulas/common/nouveau/blacklist-nouveau.conf
    - user: root
    - group: root
    - mode: "0644"
{% endif %}
