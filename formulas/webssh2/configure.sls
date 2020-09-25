include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  grains.present:
    - value: True
  module.run:
    - name: mine.send
    - m_name: spawnzero_complete
    - kwargs:
        mine_function: grains.item
    - args:
      - spawnzero_complete
    - onchanges:
      - grains: spawnzero_complete

{% else %}

check_spawnzero_status:
  module.run:
    - name: spawnzero.check
    - type: {{ grains['type'] }}
    - retry:
        attempts: 10
        interval: 30
    - unless:
      - fun: grains.equals
        key: build_phase
        value: configure

{% endif %}

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
