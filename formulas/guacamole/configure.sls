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

/etc/guacamole/guacamole.properties:
  file.managed:
    - contents: |
        guacd-hostname: localhost
        guacd-port:     4822

/etc/guacamole/user-mapping.xml:
  file.managed:
    - contents: |
        <user-mapping>
          <authorize username="foo" password="bar">
          </authorize>
        </user-mapping>
        
guacd_service:
  service.running:
    - enable: True
    - name: guacd
    - watch:
      - file: /etc/guacamole/guacamole.properties

tomcat_service:
  service.running:
    - enable: True
    - name: tomcat9
    - watch:
      - file: /etc/guacamole/guacamole.properties
