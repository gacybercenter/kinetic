# Step 9: Join additional nodes (excluding the node that was bootstrapped)
{% for node in control_nodes %}
# Check if the node has the 'k8s_bootstrapped' grain set to 'true'
{% set is_bootstrapped = salt.saltutil.runner('grains.get', kwarg={'key': 'k8s_bootstrapped', 'tgt': node}) == 'true' %}
{% if not is_bootstrapped %}
# Fetch pillar data for the current node to check if it should join as a control plane node
{% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
{% set is_control_plane = node_pillar.get('k8s_control_plane', False) == True %}
reset_{{ node }}_if_needed:
  salt.function:
    - name: kubeadm.reset
    - onlyif:
      - test -f /etc/kubernetes/admin.conf  # Reset if already joined
    - tgt: '{{ node }}'  # Target specific control node for reset

join_{{ node }}_to_cluster:
  salt.function:
    - name: kubeadm.join
    - api_server_endpoint: "{{ vip }}:6443"  # Use VIP as the endpoint
    - control_plane: {{ is_control_plane }}  # Join as control plane node based on pillar data
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf  # Only join if not already joined
    - tgt: '{{ node }}'  # Target specific control node
    - require:
      - salt: init_kubernetes_cluster
      - salt: upload_certs
      - salt: create_join_token
      - salt: reset_{{ node }}_if_needed
{% endif %}
{% endfor %}