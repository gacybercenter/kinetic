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

include:
  - /formulas/{{ grains['role'] }}/install
  - /formulas/common/fluentd/configure

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}
{% import 'formulas/common/macros/constructor.sls' as constructor with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

local_settings:
  file.managed:
    - name: /etc/openstack-dashboard/local_settings.py
    - source: salt://formulas/horizon/files/local_settings.py
    - template: jinja
    - defaults:
        webroot: horizon
        secret_key: /var/lib/openstack-dashboard/secret_key
        memcached_servers: {{ constructor.memcached_url_constructor()|yaml_encode }}
        keystone_url: {{ pillar['endpoints']['internal'] }}
        allowed_hosts: [{{ pillar['haproxy']['dashboard_domain'] }}]
        timezone: {{ pillar['timezone'] }}
        session_timeout: {{ pillar['horizon']['session_timeout'] }}
        default_dns_nameservers: {{ pillar['networking']['addresses']['float_dns'] }}
{% if salt['pillar.get']('horizon:theme:url', False) != False %}
        theming: |
            DEFAULT_THEME = '{{ pillar['horizon']['theme']['name'] }}'
            SITE_BRANDING = "{{ pillar['horizon']['theme']['site_branding'] }}"
            SITE_BRANDING_LINK = "{{ pillar['horizon']['theme']['site_branding_link'] }}"
            AVAILABLE_THEMES = [
                ('{{ pillar['horizon']['theme']['name'] }}', '{{ pillar['horizon']['theme']['name'] }}', 'themes/{{ pillar['horizon']['theme']['name'] }}')
            ]
{% else %}
        theming: |
            DEFAULT_THEME = 'default'
            AVAILABLE_THEMES = [
                ('default', 'default', 'themes/default')
            ]
{% endif %}

### ref: https://bugs.launchpad.net/horizon/+bug/1880188
#swift_ceph_patch:
#  file.line:
#    - name: /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/swiftclient/client.py
#    - content: parsed = urlparse(urljoin(url, '/swift/info'))
#    - match: parsed = urlparse(urljoin(url, '/info'))
#    - mode: replace

apache_conf:
  file.managed:
    - name: /etc/apache2/conf-enabled/openstack-dashboard.conf
    - source: salt://formulas/horizon/files/uca-dashboard.conf

/var/www/html/index.html:
  file.managed:
    - source: salt://formulas/horizon/files/index.html
    - template: jinja
    - defaults:
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
        alias: horizon

secret_key:
  file.managed:
    - name: /var/lib/openstack-dashboard/secret_key
    - user: horizon
    - group: horizon
    - mode: "0600"
    - contents_pillar: horizon:horizon_secret_key

{% if salt['pillar.get']('horizon:theme:url', False) != False %}
install_theme:
  git.latest:
    - name: {{ salt['pillar.get']('horizon:theme:url') }}
    - target: /usr/share/openstack-dashboard/openstack_dashboard/themes/{{ salt['pillar.get']('horizon:theme:name') }}
    - branch: {{ salt['pillar.get']('horizon:theme:branch') }}
{% endif %}

# TODO(chateaulav): Need to validate continued need for pyScss patch
#pyScss_deprecation_patch:
#  file.managed:
#    - names:
#      - /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/scss/namespace.py:
#        - source: salt://formulas/horizon/files/namespace.py
#      - /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/scss/types.py:
#        - source: salt://formulas/horizon/files/types.py
# /temporary patches for pyScss

configure-collect-static:
  cmd.run:
    - name: python3 manage.py collectstatic --noinput
    - cwd: /usr/share/openstack-dashboard/
    - require:
      - file: local_settings
      - file: apache_conf
    - onchanges:
      - git: install_theme
      - file: local_settings
      - sls: /formulas/horizon/install

configure-compress-static:
  cmd.run:
    - name: python3 manage.py compress
    - cwd: /usr/share/openstack-dashboard/
    - onchanges:
      - cmd: configure-collect-static
    - require:
      - cmd: configure-collect-static



apache2_service:
  service.running:
    - name: apache2
    - enable: true
    - watch:
      - file: local_settings
      - file: secret_key
      - file: apache_conf
      - git: install_theme
      - cmd: configure-compress-static
      #- file: swift_ceph_patch
