include:
  - /formulas/antora/install
  - formulas/common/base
  - formulas/common/networking

{% if grains['spawning'] == 0 %}

spawnzero_complete:
  event.send:
    - name: {{ grains['type'] }}/spawnzero/complete
    - data: "{{ grains['type'] }} spawnzero is complete."

{% endif %}

/root/site.yml:
  file.managed:
    - source: salt://formulas/antora/files/site/yml
    - template: jinja
    - defaults:
        antora_docs_repo: {{ pillar['antora_docs_repo'] }}
