# Orchestration script to deploy kube-vip and bootstrap a High Availability Kubernetes cluster
# Dynamically pulls VIP and control nodes from pillar data

# Fetch pillar data for the 'bmo' minion
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': 'bmo'}) %}
# Get VIP and control nodes from pillar data with safer handling
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set control_nodes = res_k8s.get('control_nodes', ['master-rsc-0']) %}
{% set first_control_node = control_nodes[0] if control_nodes else 'master-rsc-0' %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases

# Debug pillar data to ensure it's available
debug_pillar_data:
  cmd.run:
    - name: echo "VIP {{ vip }}, Control Nodes {{ control_nodes }}, First Node {{ first_control_node }}, Interface {{ interface }}"
    - tgt: '*'
    - output_loglevel: debug

# Step 1: Ensure Kubernetes dependencies are installed on all control plane nodes
k8s_deps:
  salt.state:
    - tgt: '{{ control_nodes|join(",") }}'
    - tgt_type: list
    - sls: /formulas/common/k8s/configure  # Installs Kubernetes dependencies (kubeadm, kubelet, etc.)

# Step 2: Download and extract kube-vip binary on all control plane nodes
download_kube_vip:
  salt.function:
    - name: cmd.run
    - cmd: |
        curl -sL https://github.com/kube-vip/kube-vip/releases/download/{{ kube_vip_version }}/kube-vip_Linux_amd64.tar.gz -o /tmp/kube-vip.tar.gz &&
        tar -xzf /tmp/kube-vip.tar.gz -C /usr/local/bin/ &&
        chmod +x /usr/local/bin/kube-vip &&
        rm /tmp/kube-vip.tar.gz
    - creates: /usr/local/bin/kube-vip  # Only run if the binary doesn't exist
    - tgt: '{{ control_nodes|join(",") }}'
    - tgt_type: list
    - require:
      - salt: k8s_deps

# Step 3: Create kube-vip manifest for static pod on all control plane nodes
create_kube_vip_manifest:
  salt.function:
    - name: file.managed
    - path: /etc/kubernetes/manifests/kube-vip.yaml
    - contents: |
        apiVersion: v1
        kind: Pod
        metadata:
          name: kube-vip
          namespace: kube-system
        spec:
          containers:
          - name: kube-vip
            image: ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
            imagePullPolicy: IfNotPresent
            args:
            - manager
            env:
            - name: vip_arp
              value: "true"
            - name: port
              value: "6443"
            - name: vip_interface
              value: {{ interface }}
            - name: vip_cidr
              value: "32"
            - name: vip_address
              value: {{ vip }}
            - name: vip_leaseduration
              value: "15"
            - name: vip_renewdeadline
              value: "10"
            - name: vip_retryperiod
              value: "2"
            - name: node_selector
              value: "true"
            - name: enableServicesElection
              value: "true"
            resources:
              limits:
                cpu: 100m
                memory: 128Mi
              requests:
                cpu: 100m
                memory: 128Mi
          hostNetwork: true
          restartPolicy: Always
    - tgt: '{{ control_nodes|join(",") }}'
    - tgt_type: list
    - require:
      - salt: download_kube_vip

# Step 4: Ensure kubelet is running to pick up the static pod manifest (kube-vip)
start_kubelet:
  salt.function:
    - name: service.running
    - name: kubelet
    - enable: True
    - tgt: '{{ control_nodes|join(",") }}'
    - tgt_type: list
    - require:
      - salt: create_kube_vip_manifest

# Step 5: Wait for kube-vip to be active on one of the nodes (check VIP reachability)
wait_for_vip:
  salt.function:
    - name: cmd.run
    - cmd: |
        timeout 60 bash -c "until curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null 2>&1; do
          echo 'Waiting for kube-vip to be active...'; sleep 5; done" &&
        echo "VIP {{ vip }} is reachable" || echo "Timeout waiting for VIP"
    - tgt: '{{ first_control_node }}'
    - require:
      - salt: start_kubelet

# Step 6: Initialize Kubernetes cluster on the first control node with VIP as control-plane-endpoint
init_kubernetes_cluster:
  salt.function:
    - name: kubeadm.init
    - pod_network_cidr: "10.244.0.0/16"
    - service_cidr: "10.96.0.0/12"
    - kubernetes_version: "v1.24.0"
    - control_plane_endpoint: "{{ vip }}:6443"  # Use VIP for HA control plane
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf  # Only initialize if not already done
    - tgt: '{{ first_control_node }}'  # Target only the first control node for initialization
    - require:
      - salt: wait_for_vip

# Step 7: Upload certificates for control plane joining (run on first control node after init)
upload_certs:
  salt.function:
    - name: kubeadm.upload_certs
    - onlyif:
      - test -f /etc/kubernetes/admin.conf  # Only run if cluster is initialized
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - require:
      - salt: init_kubernetes_cluster

# Step 8: Create a token for joining nodes (run on first control node after init)
create_join_token:
  salt.function:
    - name: kubeadm.token_create
    - ttl: "24h"  # Token time-to-live, adjust as needed
    - usages: ['signing', 'authentication']
    - onlyif:
      - test -f /etc/kubernetes/admin.conf  # Only run if cluster is initialized
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - require:
      - salt: init_kubernetes_cluster

# Step 9: Join additional control plane nodes (if any exist beyond the first)
{% for node in control_nodes[1:] if control_nodes|length > 1 %}
reset_{{ node }}_if_needed:
  salt.function:
    - name: kubeadm.reset
    - onlyif:
      - test -f /etc/kubernetes/admin.conf  # Reset if already joined
    - tgt: '{{ node }}'  # Target specific control node for reset
    - require:
      - salt: start_kubelet

join_{{ node }}_to_cluster:
  salt.function:
    - name: kubeadm.join
    - api_server_endpoint: "{{ vip }}:6443"  # Use VIP as the endpoint
    - control_plane: True  # Join as control plane node
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf  # Only join if not already joined
    - tgt: '{{ node }}'  # Target specific control node
    - require:
      - salt: init_kubernetes_cluster
      - salt: upload_certs
      - salt: create_join_token
      - salt: reset_{{ node }}_if_needed
{% endfor %}