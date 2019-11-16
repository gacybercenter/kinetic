include:
  - formulas/common/base
  - formulas/common/networking
  - formulas/horizon/install
  - formulas/horizon/install-zun-ui

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

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
{% for server, address in salt['mine.get']('type:memcached', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
        memcached_servers: {{ address[0] }}:11211
{% endfor %}
        keystone_url: {{ pillar['endpoints']['internal'] }}
        allowed_hosts: [{{ pillar['haproxy']['dashboard_domain'] }}]
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
{% elif grains['os_family'] == 'RedHat' %}

secret_key:
  file.managed:
    - name: /var/lib/openstack-dashboard/secret_key
    - user: apache
    - group: apache
    - mode: 600

{% endif %}

{% if salt['pillar.get']('horizon:theme:url', False) != False %}
install_theme:
  git.latest:
    - name: {{ salt['pillar.get']('horizon:theme:url') }}
    - target: /usr/share/openstack-dashboard/openstack_dashboard/themes/{{ salt['pillar.get']('horizon:theme:name') }}
    - branch: {{ salt['pillar.get']('horizon:theme:branch') }}
{% endif %}

apache2_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
    - require:
      - file: local_settings
    - watch:
      - file: local_settings
      - file: secret_key
      - file: apache_conf
      - git: install_theme
