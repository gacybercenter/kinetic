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
{% endif %}

docs_source:
  git.latest:
    - name: {{ pillar ['antora']['repo_url'] }}
    - target: /root/src/

/root/site.yml:
  file.managed:
    - source: salt://formulas/antora/files/site.yml
    - template: jinja
    - defaults:
        antora_docs_repo: {{ pillar ['antora']['repo_url'] }}
        docs_domain: {{ pillar['haproxy']['docs_domain'] }}
        antora_theme_url: {{ pillar ['antora']['theme_url'] }}

antora generate --fetch /root/site.yml:
  cmd.run:
    - onchanges:
      - git: docs_source

apache2_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
