{% set k8s = salt['pillar.get']('k8s') %}
{% set minions = salt.saltutil.runner('manage.up') %}
{% set rook_minion = minions | select('match', 'rook-rsc') | first %}
# Fetch pillar data for the selected minion if found
{% set rook = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': rook_minion}) %}
{% set namespace = rook.get('rook:namespace') %}

debug_join_params_{{ rook_minion }}:
  cmd.run:
    - name: echo "{{ namespace }}"
    - tgt: '{{ rook_minion }}'
    - output_loglevel: debug