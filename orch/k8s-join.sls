# Fetch pillar data for the 'bmo' minion to get VIP and node list
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': 'bmo'}) %}
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set k8s_nodes = res_k8s.get('k8s_nodes', ['master-rsc-0']) %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases

# Find the first control node (bootstrapped node) to retrieve the join parameters
{% set first_control_node = '' %}
{% for node in k8s_nodes %}
  {% set grain_result = salt.saltutil.cmd(tgt=node, fun='grains.get', arg=['k8s_bootstrapped']) %}
  {% if grain_result.get(node, {}).get('ret', '') == 'true' and first_control_node == '' %}
    {% set first_control_node = node %}
  {% endif %}
{% endfor %}
# Fallback to the first node in the list if no bootstrapped node is found
{% if first_control_node == '' %}
  {% set first_control_node = k8s_nodes[0] if k8s_nodes else 'master-rsc-0' %}
{% endif %}

# Retrieve the join parameters from the bootstrapped node
{% set join_params_result = salt.saltutil.cmd(tgt=first_control_node, fun='kubeadm.join_params') %}
{% set join_params_data = join_params_result.get(first_control_node, {}).get('ret', {}) %}
{% set join_token = join_params_data.get('token', '') %}
{% set cert_key = join_params_data.get('certificate_key', '') %}
{% set ca_cert_hash = join_params_data.get('discovery', {}).get('bootstrapToken', {}).get('caCertHashes', [''])[0] if join_params_data.get('discovery', {}).get('bootstrapToken', {}).get('caCertHashes', []) else '' %}

# Debug the retrieved join parameters (optional, for troubleshooting)
debug_join_params:
  cmd.run:
    - name: echo "Join Token {{ join_token }}, Cert Key {{ cert_key }}, CA Cert Hash {{ ca_cert_hash }}, Bootstrapped Node {{ first_control_node }}"
    - tgt: '*'
    - output_loglevel: debug

# # Step 9: Join additional nodes (excluding the node that was bootstrapped)
# {% for node in k8s_nodes %}
# # Check if the node has the 'k8s_bootstrapped' grain set to 'true'
# {% set grain_result = salt.saltutil.cmd(tgt=node, fun='grains.get', arg=['k8s_bootstrapped']) %}
# {% set is_bootstrapped = grain_result.get(node, {}).get('ret', '') == 'true' %}
# {% if not is_bootstrapped %}
# # Fetch pillar data for the current node to check if it should join as a control plane node
# {% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
# {% set is_control_plane = node_pillar.get('k8s_control_plane', False) == True %}

# # Step 1: Ensure Kubernetes dependencies are installed on the node
# k8s_deps_{{ node }}:
#   salt.state:
#     - tgt: '{{ node }}' 
#     - sls: /formulas/common/k8s/configure  # Installs Kubernetes dependencies (kubeadm, kubelet, etc.)

# # Conditional Steps for Control Plane Nodes: Install kube-vip if the node is a control plane node
# {% if is_control_plane %}
# # Step 2: Pull kube-vip container image using containerd
# pull_kube_vip_image_{{ node }}:
#   salt.function:
#     - name: cmd.run
#     - kwarg:
#         cmd: ctr image pull ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
#         onlyif: test ! -f /etc/kubernetes/manifests/kube-vip.yaml  # Only run if manifest doesn't exist
#     - tgt: '{{ node }}' 
#     - require:
#       - salt: k8s_deps_{{ node }}

# # Step 3: Run kube-vip container to generate the manifest for static pod
# generate_kube_vip_manifest_{{ node }}:
#   salt.function:
#     - name: cmd.run
#     - kwarg:
#         cmd: |
#           mkdir -p /etc/kubernetes/manifests &&
#           ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }} vip /kube-vip manifest pod \
#             --interface {{ interface }} \
#             --address {{ vip }} \
#             --k8sConfigPath /etc/kubernetes/super-admin.conf \
#             --controlplane \
#             --services \
#             --arp \
#             --leaderElection > /etc/kubernetes/manifests/kube-vip.yaml
#         creates: /etc/kubernetes/manifests/kube-vip.yaml  # Only run if the manifest doesn't exist
#     - tgt: '{{ node }}' 
#     - require:
#       - salt: pull_kube_vip_image_{{ node }}
# {% endif %}

# # Step 4: Reset if needed
# reset_{{ node }}_if_needed:
#   salt.function:
#     - name: kubeadm.reset
#     - onlyif:
#       - test -f /etc/kubernetes/admin.conf  # Reset if already joined
#     - tgt: '{{ node }}'  # Target specific node for reset

# # Step 5: Join the node to the cluster
# join_{{ node }}_to_cluster:
#   salt.function:
#     - name: kubeadm.join
#     - kwarg:
#         api_server_endpoint: "{{ vip }}:6443"  # Use VIP as the endpoint
#         cri_socket: unix:///var/run/crio/crio.sock
#         token: "{{ join_token }}"  # Use the retrieved join token
#         {% if is_control_plane %}
#         control_plane: True  # Join as control plane node based on pillar data
#         certificate_key: "{{ cert_key }}"  # Required for control plane nodes
#         {% endif %}
#     - onlyif:
#       - test ! -f /etc/kubernetes/admin.conf  # Only join if not already joined
#     - tgt: '{{ node }}'  # Target specific node
#     - require:
#       - salt: reset_{{ node }}_if_needed
#       {% if is_control_plane %}
#       - salt: generate_kube_vip_manifest_{{ node }}
#       {% endif %}
# {% endif %}
# {% endfor %}