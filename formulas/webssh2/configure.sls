include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

{% endif %}

webssh2:
  user.present

/var/www/html/app/config.json:
  file.managed:
    - source: salt://formulas/webssh2/files/config.json
    - template: jinja
    - defaults:
        allowed_subnets: {{ pillar['networking']['subnets']['public'] }}
        session_name: {{ pillar['webssh2']['session_name'] }}
        session_secret: {{ pillar['webssh2']['session_secret'] }}

/etc/systemd/system/webssh2.service:
  file.managed:
    - source: salt://formulas/webssh2/files/webssh2.service
    - mode: 644

webssh2_service:
  service.running:
    - enable: True
    - name: webssh2
    - watch:
      - file: /var/www/html/app/config.json
