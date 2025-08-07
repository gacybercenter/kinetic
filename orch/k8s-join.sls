# Fetch pillar data for the 'bmo' minion to get VIP and node list
{% set bootstrap_node = salt['pillar.get']('bootstrap_node') %}
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': bootstrap_node}) %}
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set k8s_nodes = res_k8s.get('k8s_nodes', ['master-rsc-0']) %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases


# Debug the retrieved join parameters (optional, for troubleshooting)
debug_join_params:
  cmd.run:
    - name: echo "Bootstrap {{ bootstrap_node }} }}" #, Cert Key {{ cert_key }}, CA Cert Hash {{ ca_cert_hash }}, Bootstrapped Node {{ first_control_node }}"
    - tgt: '*'
    - output_loglevel: debug