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

{% for host in pillar['bmh'] %}
bmh-userdata-{{ host['name'] }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-userdata-{{ host['name'] }}.yaml
    - source: salt://formulas/bmo/files/cloudinit.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ host['name'] }}
        pass: {{ pillar['hosts']['compute']['root_password_crypted'] }}

bmh-userdata-{{ host['name'] }}-secret:
  cmd.run:
    - name: kubectl -n {{ pillar['bmo_namespace'] }} create secret generic userdata-{{ host['name'] }} --from-file=userData={{ pillar['script_dir'] }}/bmh-userdata-{{ host['name'] }}.yaml
    - onchanges:
      - file: bmh-userdata-{{ host['name'] }}-temp

bmh-networkdata-{{ host['name'] }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-networkdata-{{ host['name'] }}.yaml
    - source: salt://formulas/bmo/files/network-data.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ host['name'] }}
        mac: {{ host['bootMACAddress'] }}
        domain: {{ pillar['dhcp-options']['domain'] }}
        ip: {{ host['network']['ip'] }}
        prefix: {{ pillar['networking']['subnets']['management'].split("/")[1] }} 
        gateway: {{ pillar['dhcp-options']['mgmt_gateway'] }}
        nameserver: {{ pillar['dhcp-options']['dns'] }}

bmh-networkdata-{{ host['name'] }}-secret:
  cmd.run:
    - name: kubectl -n {{ pillar['bmo_namespace'] }} create secret generic networkdata-{{ host['name'] }} --from-file=networkData={{ pillar['script_dir'] }}/bmh-networkdata-{{ host['name'] }}.yaml
    - onchanges:
      - file: bmh-networkdata-{{ host['name'] }}-temp

bmh-host-{{ host['name'] }}-temp:
  file.managed:
    - name: {{ pillar['script_dir'] }}/bmh-{{ host['name'] }}-temp.yaml
    - source: salt://formulas/bmo/files/bmh.j2
    - mode: 644
    - template: jinja
    - defaults:
        name: {{ host['name'] }}
        namespace: {{ pillar['bmo_namespace'] }}
        online: {{ host['online'] }}
        address: {{ host['bmc']['address'] }}
        bootMACAddress: {{ host['bootMACAddress'] }}
        checksum: {{ host['image']['checksum'] }}
        url: {{ host['image']['url'] }}
        format: {{ host['image']['format'] }}
        rootdevice: {{ host['rootDeviceHints']['deviceName'] }}
        userdata: userdata-{{ host['name'] }}
        networkdata: networkdata-{{ host['name'] }}

bmh-{{ host['name'] }}:
  cmd.run:
    - name: kubectl apply -f {{ pillar['script_dir'] }}/bmh-{{ host['name'] }}-temp.yaml
    - onchanges:
      - file: bmh-host-{{ host['name'] }}-temp
{% endfor %}