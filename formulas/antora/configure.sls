include:
  - /formulas/antora/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."
    - onchanges:
      - file: /etc/apache2/sites-available/000-default.conf

{% endif %}

/etc/apache2/sites-available/000-default.conf:
  file.managed:
    - source: salt://formulas/antora/files/000-default.conf

/root/site.yml:
  file.managed:
    - source: salt://formulas/antora/files/site.yml
    - template: jinja
    - defaults:
        antora_docs_repo: {{ pillar['antora_docs_repo'] }}
        docs_domain: {{ pillar['haproxy']['docs_domain'] }}

antora generate --fetch /root/site.yml:
  cmd.run:
    - require:
      - /root/site.yml

apache2_service:
  service.running:
    - name: apache2
    - watch:
      - file: /etc/apache2/sites-available/000-default.conf
