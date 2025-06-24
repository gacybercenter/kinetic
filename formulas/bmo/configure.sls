include:
  - /formulas/bmo/install

deploy_script:
  file.managed:
    - name: {{ pillar['script_dir'] }}/deploy_state.sh
    - source: salt://formulas/bmo/files/deploy.j2
    - mode: 700
    - template: jinja

bmc-auth-secret-template:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmc-auth.yaml
    - source: salt://formulas/bmo/files/bmc-auth.j2
    - mode: 644
    - template: jinja
bmc-auth-secret:
  cmd.run:
    - name: kubectl apply -n {{ pillar['bmo_namespace'] }} -f {{ pillar['script_dir'] }}/bmc-auth.yaml
    - onchanges:
      - file: bmc-auth-secret-template

{% for name, host in pillar['bmh'].items() %}
bmh-userdata-{{ name }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-userdata-{{ name }}.yaml
    - source: salt://formulas/bmo/files/cloudinit.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ name }}
        pass: {{ pillar['hosts']['compute']['root_password_crypted'] }}

bmh-userdata-{{ name }}-secret:
  cmd.run:
    - name: kubectl -n {{ pillar['bmo_namespace'] }} delete secret userdata-{{ name }} && kubectl -n {{ pillar['bmo_namespace'] }} create secret generic userdata-{{ name }} --from-file=userData={{ pillar['script_dir'] }}/bmh-userdata-{{ name }}.yaml
    - onchanges:
      - file: bmh-userdata-{{ name }}-temp

bmh-networkdata-{{ name }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-networkdata-{{ name }}.yaml
    - source: salt://formulas/bmo/files/network-data.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ name }}
        mac: {{ host['bootMACAddress'] }}
        domain: {{ pillar['dhcp-options']['domain'] }}
        ip: {{ host['network']['management_ip'] }}
        prefix: {{ pillar['networking']['subnets']['management'].split("/")[1] }} 
        gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
        nameserver: {{ pillar['dhcp-options']['dns'] }}

bmh-networkdata-{{ name }}-secret:
  cmd.run:
    - name: kubectl -n {{ pillar['bmo_namespace'] }} delete secret networkdata-{{ name }} && kubectl -n {{ pillar['bmo_namespace'] }} create secret generic networkdata-{{ name }} --from-file=networkData={{ pillar['script_dir'] }}/bmh-networkdata-{{ name }}.yaml
    - onchanges:
      - file: bmh-networkdata-{{ name }}-temp

bmh-host-{{ name }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-{{ name }}-temp.yaml
    - source: salt://formulas/bmo/files/bmh.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ name }}
        namespace: {{ pillar['bmo_namespace'] }}
        online: {{ host['online'] }}
        address: {{ host['bmc']['address'] }}
        bootMACAddress: {{ host['bootMACAddress'] }}
        checksum: {{ host['image']['checksum'] }}
        url: {{ host['image']['url'] }}
        format: {{ host['image']['format'] }}
        rootdevice: {{ host['rootDeviceHints']['deviceName'] }}
        userdata: userdata-{{ name }}
        networkdata: networkdata-{{ name }}

bmh-{{ name }}:
  cmd.run:
    - name: kubectl -n {{ pillar['bmo_namespace'] }} delete bmh bmh-{{ name }} && kubectl apply -f {{ pillar['script_dir'] }}/bmh-{{ name }}-temp.yaml
    - onchanges:
      - file: bmh-host-{{ name }}-temp
{% endfor %}