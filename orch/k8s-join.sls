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
{% set is_control_plane = node_pillar.get('bmh:node:k8s_control_plane', False) %}
# Retrieve the join parameters from the bootstrapped node using kubeadm token create --print-join-command
{% set join_command_result = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=['kubeadm token create --print-join-command |awk '{print $7}']) %}
{% set join_command_output = join_command_result.get(bootstrap_node, {}).get('ret', '') %}

# Retrieve the certificate key for control plane nodes
{% set cert_upload_result = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=['kubeadm certs certificate-key']) %}
{% set cert_key = cert_upload_result.get(bootstrap_node, {}).get('ret', '') %}

# Step 1: Ensure Kubernetes dependencies are installed on the node
k8s_deps_{{ node }}:
  salt.state:
    - tgt: '{{ node }}' 
    - sls: /formulas/common/k8s/configure  # Installs Kubernetes dependencies (kubeadm, kubelet, etc.)

# Debug the retrieved join parameters (optional, for troubleshooting)
debug_join_params_{{ node }}:
  cmd.run:
    - name: echo "Join Token {{ join_token }}, Cert Key {{ cert_key }}, CA Cert Hash {{ ca_cert_hash }}, Bootstrapped Node {{ bootstrap_node }}"
    - tgt: '{{ node }}'
    - output_loglevel: debug

# Conditional Steps for Control Plane Nodes: Install kube-vip if the node is a control plane node
{% if node_pillar['bmh'][node]['k8s_control_plane'] == True %}
# Step 2: Pull kube-vip container image using containerd
pull_kube_vip_image_{{ node }}:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: ctr image pull ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
        onlyif: test ! -f /etc/kubernetes/manifests/kube-vip.yaml  # Only run if manifest doesn't exist
    - tgt: '{{ node }}' 
    - require:
      - salt: k8s_deps_{{ node }}

# Step 3: Run kube-vip container to generate the manifest for static pod
generate_kube_vip_manifest_{{ node }}:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          mkdir -p /etc/kubernetes/manifests &&
          ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }} vip /kube-vip manifest pod \
            --interface {{ interface }} \
            --address {{ vip }} \
            --k8sConfigPath /etc/kubernetes/super-admin.conf \
            --controlplane \
            --services \
            --arp \
            --leaderElection > /etc/kubernetes/manifests/kube-vip.yaml
        creates: /etc/kubernetes/manifests/kube-vip.yaml  # Only run if the manifest doesn't exist
    - tgt: '{{ node }}' 
    - require:
      - salt: pull_kube_vip_image_{{ node }}
{% endif %}

{% endfor %}