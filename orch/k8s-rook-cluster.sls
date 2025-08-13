{% set k8s = salt['pillar.get']('k8s') %}
{% set minions = salt.saltutil.runner('manage.up') %}
{% set rook_minion = minions | select('match', 'rook-rsc') | first %}
# Fetch pillar data for the selected minion if found
{% set rook = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': rook_minion}) %}
{% set osd_mappings = rook.get('osd_mappings') %}

debug_join_params_{{ rook_minion }}:
  cmd.run:
    - name: echo "{{ osd_mappings }}"
    - tgt: '{{ rook_minion }}'
    - output_loglevel: debug