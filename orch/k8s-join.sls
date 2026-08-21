# Fetch pillar data for the 'bmo' minion to get VIP and other configurations
{% set bootstrap_node = salt['pillar.get']('bootstrap_node') %}
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': bootstrap_node}) %}
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases

# Allow node to be passed as an argument to the orchestration; fail if not provided
{% set node = salt['pillar.get']('node_to_join', '') %}
{% if not node %}
  {% do salt.log.error("No node specified for joining. Please provide 'node_to_join' in pillar or as an argument.") %}
  fail_no_node_specified:
    test.fail_without_changes:
      - name: "Error: No node specified for joining. Please provide 'node_to_join' in pillar or as an argument."
{% else %}
# Fetch pillar data for the specified node to check if it should join as a control plane node
{% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
# Check if the node is already part of the Kubernetes cluster
{% set node_status_check = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=["kubectl get nodes --field-selector metadata.name="+node+" -o name"]) %}
{% set node_status_output = node_status_check.get(bootstrap_node, {}).get('ret', '') %}
# Skip the node if it is already in the cluster
{% if node_status_output.strip() == "node/"+node %}
# Node is already in the cluster, skip joining
node_already_joined_{{ node }}:
  cmd.run:
    - name: echo "Node {{ node }} is already part of the cluster, skipping join process."
    - tgt: '{{ bootstrap_node }}'
    - output_loglevel: info
{% else %}
# Retrieve the join parameters from the bootstrapped node using kubeadm token create --print-join-command
{% set certkey = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=["kubeadm certs certificate-key"]) %}
{% set certkey = certkey.get(bootstrap_node, {}).get('ret', '') %}
{% set upload_certs = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=["kubeadm init phase upload-certs --upload-certs --certificate-key "+certkey]) %}
{% set join_command_result = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=["kubeadm token create --print-join-command --certificate-key "+certkey]) %}
{% set join_command_output = join_command_result.get(bootstrap_node, {}).get('ret', '') %}

# Step 1: Ensure Kubernetes dependencies are installed on the node
k8s_deps_{{ node }}:
  salt.state:
    - tgt: '{{ node }}'
    - sls: /formulas/common/k8s/configure  # Installs Kubernetes dependencies (kubeadm, kubelet, etc.)

# Debug the retrieved join parameters (optional, for troubleshooting)
debug_join_params_{{ node }}:
  cmd.run:
    - name: echo "{{ join_command_output }} --cri-socket unix:///var/run/crio/crio.sock --control-plane"
    - tgt: '{{ node }}'
    - output_loglevel: debug

# Conditional Steps for Control Plane Nodes: Install kube-vip if the node is a control plane node
{% if node_pillar['bmh'][node]['k8s_control_plane'] is defined %}
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
            --k8sConfigPath /etc/kubernetes/admin.conf \
            --controlplane \
            --services \
            --arp \
            --leaderElection > /etc/kubernetes/manifests/kube-vip.yaml
        creates: /etc/kubernetes/manifests/kube-vip.yaml  # Only run if the manifest doesn't exist
    - tgt: '{{ node }}'
    - require:
      - salt: pull_kube_vip_image_{{ node }}

# Step 5: Join the node to the cluster
join_{{ node }}_ctl_to_cluster:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          {{ join_command_output }} --cri-socket unix:///var/run/crio/crio.sock
    - tgt: '{{ node }}'
    - require:
      - salt: k8s_deps_{{ node }}
      - salt: generate_kube_vip_manifest_{{ node }}
{% else %}
{% set join_command_worker_result = salt.saltutil.cmd(tgt=bootstrap_node, fun='cmd.run', arg=["kubeadm token create --print-join-command"]) %}
{% set join_command_worker_output = join_command_worker_result.get(bootstrap_node, {}).get('ret', '') %}
join_{{ node }}_worker_to_cluster:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          {{ join_command_worker_output }} --cri-socket unix:///var/run/crio/crio.sock
    - tgt: '{{ node }}'
    - require:
      - salt: k8s_deps_{{ node }}
{% endif %}
{% endif %}
{% endif %}
