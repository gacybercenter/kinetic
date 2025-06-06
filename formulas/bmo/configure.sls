include:
  - /formulas/bmo/install

bmc-auth-secret-template:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/bmc-auth.yaml
    - source: salt://formulas/bmo/files/bmc-auth.j2
    - mode: 644
    - template: jinja
bmc-auth-secret:
  cmd.run:
    - name: kubectl apply -f {{ pillar['temp_ironic_overlay'] }}/bmc-auth.yaml
    - onchanges:
      - file: bmc-auth-secret-template

{% for host in pillar['bmh'] %}
bmh-host-{{ host['name'] }}-temp:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/bmh-{{ host['name'] }}-temp.yaml
    - source: salt://formulas/bmo/files/bmh.j2
    - mode: 644
    - template: jinja
bmh-{{ host['name'] }}:
  cmd.run:
    - name: kubectl apply -f {{ pillar['temp_ironic_overlay'] }}/bmh-{{ host['name'] }}-temp.yaml
    - onchanges:
      - file: bmh-host-{{ host['name'] }}-temp
{% endfor %}