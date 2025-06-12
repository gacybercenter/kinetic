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

bmh-userdata-{{ host['name'] }}-secret:
  cmd.run:
    - name: kubectl apply -f {{ pillar['script_dir'] }}/bmh-userdata-{{ host['name'] }}.yaml
    - onchanges:
      - file: bmh-userdata-{{ host['name'] }}-temp

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

bmh-{{ host['name'] }}:
  cmd.run:
    - name: kubectl apply -f {{ pillar['script_dir'] }}/bmh-{{ host['name'] }}-temp.yaml
    - onchanges:
      - file: bmh-host-{{ host['name'] }}-temp
{% endfor %}