include:
  - /formulas/bmo/install

bmc-auth-secret-template:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/bmc-auth.yaml
    - source: salt://formulas/bmo/files/bmc-auth.j2
    - mode: 644
    - template: jinja
bmc-auth-secret:
  kubernetes.secret_present:
    - name: bmc-auth
    - source: salt://formulas/bmo/files/bmc-auth.j2
    - template: jinja
    - onchanges:
      - file: bmc-auth-secret-template

{% for host in pillar['bmh'] %}
bmh-host-{{ host['name'] }}-temp:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/bmh-{{ host['name'] }}-temp.yaml
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
        rootdevice: {{ host['rootDeviceHints']['deviceName'] }}
bmh-{{ host['name'] }}:
  cmd.run:
    - name: kubectl apply -f {{ pillar['temp_ironic_overlay'] }}/bmh-{{ host['name'] }}-temp.yaml
    - onchanges:
      - file: bmh-host-{{ host['name'] }}-temp
{% endfor %}