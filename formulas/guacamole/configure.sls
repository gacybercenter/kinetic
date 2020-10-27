include:
  - /formulas/{{ grains['role'] }}/install

{% import 'formulas/common/macros/spawn.sls' as spawn with context %}

{% if grains['spawning'] == 0 %}

{{ spawn.spawnzero_complete() }}

{% else %}

{{ spawn.check_spawnzero_status(grains['type']) }}

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
