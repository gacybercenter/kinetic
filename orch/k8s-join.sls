{% for node in control_nodes %}
# Check if the node has the 'k8s_bootstrapped' grain set to 'true'
{% set is_bootstrapped = salt.saltutil.runner('grains.get', kwarg={'key': 'k8s_bootstrapped', 'tgt': node}) == 'true' %}
{% if not is_bootstrapped %}
# Fetch pillar data for the current node to check if it should join as a control plane node
{% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
{% set is_control_plane = node_pillar.get('k8s_control_plane', False) == True %}
# Step 1: Ensure Kubernetes dependencies are installed on all control plane nodes
k8s_deps:
  salt.state:
    - tgt: '{{ first_control_node }}' 
    - sls: /formulas/common/k8s/configure  # Installs Kubernetes dependencies (kubeadm, kubelet, etc.)

# Step 2: Pull kube-vip container image using containerd
pull_kube_vip_image:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: ctr image pull ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
        onlyif: test ! -f /etc/kubernetes/manifests/kube-vip.yaml  # Only run if manifest doesn't exist
    - tgt: '{{ first_control_node }}' 
    - require:
      - salt: k8s_deps

# Step 3: Run kube-vip container to generate the manifest for static pod
generate_kube_vip_manifest:
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
    - tgt: '{{ first_control_node }}' 
    - tgt_type: list
    - require:
      - salt: pull_kube_vip_image
# Step 9: Join additional nodes (excluding the node that was bootstrapped)
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
{% if is_control_plane == "true" %}
    - control_plane: true  # Join as control plane node based on pillar data
{% endif %}
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf  # Only join if not already joined
    - tgt: '{{ node }}'  # Target specific control node
{% endif %}
{% endfor %}