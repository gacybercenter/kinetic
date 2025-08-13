{% set k8s = salt['pillar.get']('k8s') %}
{% set rook_data = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': k8s}) %}
{% set rook = rook_data.get('rook') %}
{% set devices = rook_data.get('osd_mappings').get('storage').get('osd') %}
{% set namespace = rook.get('namespace') %}
{% set rook_version = rook.get('rook_version') %}
{% set ceph_image = rook.get('ceph_image') %}
{% set limits_cpu = rook.get('resources').get('limits').get('cpu') %}
{% set limits_memory = rook.get('resources').get('limits').get('memory') %}
{% set requests_cpu = rook.get('resources').get('requests').get('cpu') %}
{% set requests_memory = rook.get('resources').get('requests').get('memory') %}
{% set rook_role = rook.get('mon').get('node_role') %}
{% set rook_osd_role = rook.get('osd').get('node_role') %}

debug_join_params_{{ k8s }}:
  cmd.run:
    - kwarg:
        cmd: | 
          echo \
          namespace: {{ namespace }} \
          rook_version: {{ rook_version }} \
          ceph_image: {{ ceph_image }} \
          limits_cpu: {{ limits_cpu }} \
          limits_memory: {{ limits_memory }} \
          requests_cpu: {{ requests_cpu }} \
          requests_memory: {{ requests_memory }} \
          devices: {{ devices }} \
          rook_role: {{ rook_role }} \
          rook_osd_role: {{ rook_osd_role }}
    - tgt: '{{ k8s }}'
    - output_loglevel: debug

install_rook_cluster_{{ rook_version }}:
  salt.state:
    - tgt: {{ k8s }}
    - sls: /formulas/common/k8s-rook/cluster
    - pillar:
        namespace: {{ namespace }}
        rook_version: {{ rook_version }}
        ceph_image: {{ ceph_image }}
        limits_cpu: {{ limits_cpu }}
        limits_memory: {{ limits_memory }}
        requests_cpu: {{ requests_cpu }}
        requests_memory: {{ requests_memory }}
        devices: {{ devices }}
        rook_role: {{ rook_role }}
        rook_osd_role: {{ rook_osd_role }}