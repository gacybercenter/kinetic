include:
  - /formulas/pxe/install

/etc/salt/minion.d/mine_functions.conf:
  file.managed:
    - contents: |
        mine_functions:
          redfish.gather_endpoints:
            - {{ pillar ['networking']['subnets']['oob'] }}
            - {{ pillar ['api_user'] }}
            - {{ pillar ['bmc_password'] }}

https://github.com/ipxe/ipxe.git:
  git.latest:
    - target: /var/www/html/ipxe
    - user: root
    - require:
      - sls: /formulas/pxe/install

/var/www/html/ipxe/src/kinetic.ipxe:
  file.managed:
    - source: salt://formulas/pxe/files/kinetic.ipxe
    - template: jinja
    - defaults:
        pxe_record: {{ pillar['pxe_record'] }}

create_efi_module:
  cmd.run:
    - name: |
        make bin-x86_64-efi/ipxe.efi EMBED=kinetic.ipxe
    - cwd: /var/www/html/ipxe/src/
    - creates: /var/www/html/ipxe/src/bin-x86_64-efi/ipxe.efi

/var/www/html/index.html:
  file.absent

Disable default site:
  apache_site.disabled:
    - name: default

/etc/apache2/sites-available/wsgi.conf:
  file.managed:
    - source: salt://formulas/pxe/files/wsgi.conf

wsgi_site:
  apache_site.enabled:
    - name: wsgi

wsgi_module:
  apache_module.enabled:
    - name: wsgi

/var/www/html/index.py:
  file.managed:
    - source: salt://formulas/pxe/files/index.py
    - template: jinja
    - defaults:
        pxe_record: {{ pillar['pxe_record'] }}

/var/www/html/assignments:
  file.directory

{% for type in pillar['hosts'] %}
  {% if 'ubuntu' in pillar['hosts'][type]['os'] %}
/var/www/html/preseed/{{ type }}.preseed:
  file.managed:
    - source: salt://formulas/pxe/files/common.preseed
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
        master_record: {{ pillar['master_record'] }}
        transport: {{ pillar['salt_transport'] }}
    {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
      {% set cache_addresses_dict = salt['mine.get']('cache*','network.ip_addrs') %}
      {% if cache_addresses_dict == {} %}
        proxy: ""
      {% else %}
        {% for host in cache_addresses_dict %}
        proxy: http://{{ cache_addresses_dict[host][0] }}:3142
        {% endfor %}
      {% endif %}
    {% endif %}
  {% elif 'centos' in pillar['hosts'][type]['os'] %}
/var/www/html/kickstart/{{ type }}.kickstart:
  file.managed:
    - source: salt://formulas/pxe/files/common.kickstart
    - makedirs: True
    - template: jinja
    - defaults:
        proxy: {{ pillar['hosts'][type]['proxy'] }}
        root_password_crypted: {{ pillar['hosts'][type]['root_password_crypted'] }}
        zone: {{ pillar['timezone'] }}
        ntp_server: {{ pillar['hosts'][type]['ntp_server'] }}
        disk: {{ pillar['hosts'][type]['disk'] }}
        interface: {{ pillar['hosts'][type]['interface'] }}
        master_record: {{ pillar['master_record'] }}
        transport: {{ pillar['salt_transport'] }}
    {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
      {% if salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length is empty %}
        proxy: ""
      {% else %}
        {% for host, addresses in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() %}
          {%- for address in addresses -%}
            {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        proxy: http://{{ address }}:3142
            {% endif %}
          {% endfor %}
        {% endfor %}
      {% endif %}
    {% endif %}
  {% endif %}
{% endfor %}

apache2_service:
  service.running:
    - name: apache2
    - watch:
      - apache_module: wsgi_module
      - file: /etc/apache2/sites-available/wsgi.conf
      - apache_site: wsgi
      - apache_site: default

salt-minion_mine_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - file: /etc/salt/minion.d/mine_functions.conf
    - order: last
