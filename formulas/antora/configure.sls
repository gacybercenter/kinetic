include:
  - /formulas/{{ grains['role'] }}/install

{% if grains['spawning'] == 0 %}
  {% from "/formulas/common/macros/spawn.sls" import spawnzero_complete with context %}
    {{ spawnzero_complete() }}
{% endif %}

docs_source:
  git.latest:
    - name: {{ pillar ['antora']['repo_url'] }}
    - target: /root/src/

theme_source:
  file.managed:
    - name: /root/theme.zip
    - source: {{ pillar ['antora']['theme_url'] }}
    - source_hash: {{ pillar ['antora']['theme_hash_url'] }}

/root/site.yml:
  file.managed:
    - source: salt://formulas/antora/files/site.yml
    - template: jinja
    - defaults:
        antora_docs_repo: {{ pillar ['antora']['repo_url'] }}
        docs_domain: {{ pillar['haproxy']['docs_domain'] }}
        antora_theme_url: {{ pillar ['antora']['theme_url'] }}

wipe_cache:
  file.absent:
    - name: /root/.cache/antora
    - onchanges:
      - git: docs_source
      - file: /root/site.yml
      - file: theme_source

generate_site:
  cmd.run:
    - name: antora generate --fetch --clean /root/site.yml
    - require:
      - file: wipe_cache
    - onchanges:
      - git: docs_source
      - file: /root/site.yml
      - file: theme_source

apache2_service:
  service.running:
{% if grains['os_family'] == 'Debian' %}
    - name: apache2
{% elif grains['os_family'] == 'RedHat' %}
    - name: httpd
{% endif %}
    - enable: true
