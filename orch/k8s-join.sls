# Fetch pillar data for the 'bmo' minion to get VIP and node list
{% set bootstrap_node = salt['pillar.get']('bootstrap_node') %}
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': bootstrap_node}) %}
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set k8s_nodes = res_k8s.get('k8s_nodes', ['master-rsc-0']) %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases


# # Step 9: Join additional nodes (excluding the node that was bootstrapped)
{% for node in k8s_nodes if not node == bootstrap_node %}
# Fetch pillar data for the current node to check if it should join as a control plane node
{% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
{% set is_control_plane = node_pillar.get('k8s_control_plane', False) == True %}
debug_node_name:
  cmd.run:
    - name: echo "Node {{ node }}"
    - tgt: {{ node }}
    
{% endfor %}
# Debug the retrieved join parameters (optional, for troubleshooting)
debug_join_params:
  cmd.run:
    - name: echo "Bootstrap {{ bootstrap_node }} }} VIP {{ vip }}"
    - tgt: '*'
    - output_loglevel: debug