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
    - name: 000-default

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
/var/www/html/configs/{{ type }}:
  file.managed:
  {% if 'ubuntu' in pillar['hosts'][type]['os'] %}
    - source: salt://formulas/pxe/files/common.preseed
  {% elif 'centos' in pillar['hosts'][type]['os'] %}
    - source: salt://formulas/pxe/files/common.kickstart
  {% endif %}
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
  {% if pillar['hosts'][type]['proxy'] == 'pull_from_mine' %}
    - context:
    {% if salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain')|length == 0 %}
        proxy: ""
    {% else %}
      ##pick a random cache and iterate through its addresses, choosing only the management address
      {% for address in salt['mine.get']('role:cache', 'network.ip_addrs', tgt_type='grain') | dictsort() | random() | last ()%}
        {%- if salt['network']['ip_in_subnet'](address, pillar['networking']['subnets']['management']) %}
        proxy: http://{{ address }}:3142
        {% endif %}
      {% endfor %}
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
      - apache_site: 000-default

salt-minion_mine_watch:
  cmd.run:
    - name: 'salt-call service.restart salt-minion'
    - bg: True
    - onchanges:
      - file: /etc/salt/minion.d/mine_functions.conf
    - order: last
