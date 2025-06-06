include:
  - /formulas/bmo/install

bmc-auth-secret-template:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/bmc-auth.yaml
    - source: salt://formulas/bmo/files/bmc-auth.j2
    - mode: 644
    - template: jinja
    - require:
      - file: temp_overlay_dirs
bmc-auth-secret:
  cmd.run:
    - name: kubectl apply -f {{ pillar['temp_ironic_overlay'] }}/bmc-auth.yaml
    - onchanges:
      - file: bmc-auth-secret-template