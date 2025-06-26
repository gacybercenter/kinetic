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
ensure_bmh_{{ name }}present:
  module.run:
    - name: kinetic-k8s.bmh_replace
    - namespace: baremetal-operator-system
    - bmh_name: {{ name }}
    - pillar_data: {{ pillar['bmh'].get(name) }}
    - bmh_template_path: salt://formulas/bmo/files/bmh.j2
    - network_template_path: salt://formulas/bmo/files/network-data.j2
    - userdata_template_path: salt://formulas/bmo/files/cloudinit.j2
{% endfor %}