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
ensure_{{ name }}_networkdata_present:
  module.run:
    - name: kinetic-k8s.networkdata_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - network_template_path: salt://formulas/bmo/files/network-data.j2
ensure_{{ name }}_userdata_present:
  module.run:
    - name: kinetic-k8s.userdata_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - userdata_template_path: salt://formulas/bmo/files/cloudinit.j2
    - require:
      - module: ensure_{{ name }}_networkdata_present
ensure_{{ name }}_bmh_present:
  module.run: 
    - name: kinetic-k8s.bmh_present
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - bmh_template_path: salt://formulas/bmo/files/bmh.j2
    - require:
      - module: ensure_{{ name }}_networkdata_present
      - module: ensure_{{ name }}_userdata_present
{% endfor %}