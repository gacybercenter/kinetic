include:
  - formulas/common/base
  - formulas/common/networking
  - /formulas/horizon/install
  - /formulas/horizon/install-zun-ui

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/etc/openstack-dashboard/local_settings.py:
  file.managed:
    - source: salt://formulas/horizon/files/local_settings.py
    - template: jinja
    - defaults:
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

/etc/apache2/conf-enabled/openstack-dashboard.conf:
  file.managed:
    - source: salt://formulas/horizon/files/openstack-dashboard.conf

/var/www/html/index.html:
  file.managed:
    - source: salt://formulas/horizon/files/index.html
    - template: jinja
    - defaults:
        dashboard_domain: {{ pillar['haproxy']['dashboard_domain'] }}

/var/lib/openstack-dashboard/secret_key:
  file.managed:
    - user: horizon
    - group: horizon

{% if salt['pillar.get']('horizon:theme:url', False) != False %}
install_theme:
  git.latest:
    - name: {{ salt['pillar.get']('horizon:theme:url') }}
    - target: /usr/share/openstack-dashboard/openstack_dashboard/themes/{{ salt['pillar.get']('horizon:theme:name') }}
    - branch: {{ salt['pillar.get']('horizon:theme:branch') }}
{% endif %}

apache2_service:
  service.running:
    - name: apache2
    - watch:
      - file: /etc/openstack-dashboard/local_settings.py
      - file: /var/lib/openstack-dashboard/secret_key
      - file: /etc/apache2/conf-enabled/openstack-dashboard.conf
      - git: install_theme
