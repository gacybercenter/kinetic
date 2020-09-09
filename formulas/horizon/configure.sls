include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

local_settings:
  file.managed:
{% if grains['os_family'] == 'Debian' %}
    - name: /etc/openstack-dashboard/local_settings.py
{% elif grains['os_family'] == 'RedHat' %}
    - name: /etc/openstack-dashboard/local_settings
{% endif %}
    - source: salt://formulas/horizon/files/local_settings.py
    - template: jinja
    - defaults:
{% if grains['os_family'] == 'Debian' %}
        webroot: horizon
{% elif grains['os_family'] == 'RedHat' %}
        webroot: dashboard
{% endif %}
{% if grains['os_family'] == 'Debian' %}
        secret_key: /var/lib/openstack-dashboard/secret_key
{% elif grains['os_family'] == 'RedHat' %}
        secret_key: /var/lib/openstack-dashboard/secret_key
{% endif %}
        memcached_servers: |-
          {{ ""|indent(10) }}
          {%- for host, addresses in salt['mine.get']('role:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() -%}
            {%- for address in addresses -%}
              {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) -%}
          '{{ address }}:11211'
              {%- endif -%}
            {%- endfor -%}
            {% if loop.index < loop.length %},{% endif %}
          {%- endfor %}
        keystone_url: {{ pillar['endpoints']['internal'] }}
        allowed_hosts: [{{ pillar['haproxy']['dashboard_domain'] }}]
        tiemzone: {{ pillar['timezone'] }}
        session_timeout: {{ pillar['horizon']['session_timeout'] }}
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
swift_ceph_patch:
  file.line:
{% if grains['os_family'] == 'RedHat' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}.{{ grains['pythonversion'][1] }}/site-packages/swiftclient/client.py
{% elif grains['os_family'] == 'Debian' %}
    - name: /usr/lib/python{{ grains['pythonversion'][0] }}/dist-packages/swiftclient/client.py
{% endif %}
    - content: parsed = urlparse(urljoin(url, '/swift/info'))
    - match: parsed = urlparse(urljoin(url, '/info'))
    - mode: replace

{% if grains['os_family'] == 'Debian' %}
apache_conf:
  file.managed:
    - name: /etc/apache2/conf-enabled/openstack-dashboard.conf
    - source: salt://formulas/horizon/files/uca-dashboard.conf
{% elif grains['os_family'] == 'RedHat' %}
apache_conf:
  file.managed:
    - name: /etc/httpd/conf.d/openstack-dashboard.conf
    - source: salt://formulas/horizon/files/rdo-dashboard.conf
{% endif %}

/var/www/html/index.html:
  file.managed:
    - source: salt://formulas/horizon/files/index.html
    - template: jinja
    - defaults:
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}
{% if grains['os_family'] == 'Debian' %}
        alias: horizon
{% elif grains['os_family'] == 'RedHat' %}
        alias: dashboard
{% endif %}

{% if grains['os_family'] == 'Debian' %}

secret_key:
  file.managed:
    - name: /var/lib/openstack-dashboard/secret_key
    - user: horizon
    - group: horizon
    - mode: 600
    - contents_pillar: horizon:horizon_secret_key
{% elif grains['os_family'] == 'RedHat' %}

secret_key:
  file.managed:
    - name: /var/lib/openstack-dashboard/secret_key
    - user: apache
    - group: apache
    - mode: 600
    - contents_pillar: horizon:horizon_secret_key

{% endif %}

{% if salt['pillar.get']('horizon:theme:url', False) != False %}
install_theme:
  git.latest:
    - name: {{ salt['pillar.get']('horizon:theme:url') }}
    - target: /usr/share/openstack-dashboard/openstack_dashboard/themes/{{ salt['pillar.get']('horizon:theme:name') }}
    - branch: {{ salt['pillar.get']('horizon:theme:branch') }}
{% endif %}

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
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
    - watch:
      - file: local_settings
      - file: secret_key
      - file: apache_conf
      - git: install_theme
      - cmd: configure-compress-static
      - file: swift_ceph_patch
