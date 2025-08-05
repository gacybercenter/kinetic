# Bootstrap a Kubernetes cluster using kubeadm

# Ensure dependencies are installed and configured
include:
  - /formulas/common/k8s/install
  - /formulas/common/k8s/configure

# Get VIP and control nodes from pillar data
{% set vip = pillar['res-k8s'].get('vip', '') %}
{% set control_nodes = pillar.get('res-k8s', {}).get('control_nodes', ['master-rsc-0']) %}
{% set first_control_node = control_nodes[0] %}

# Debug pillar data to ensure it's available
debug_pillar_data:
  cmd.run:
    - name: echo "VIP: {{ vip }}, Control Nodes: {{ control_nodes }}, First Node: {{ first_control_node }}"
    - tgt: '*'
    - output_loglevel: debug

# Check if VIP is reachable (port 6443 for Kubernetes API using curl)
check_vip_reachable:
  cmd.run:
    - name: test -n "{{ vip }}" && curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null 2>&1 && echo "reachable" || echo "unreachable" || echo "no_vip"
    - output_loglevel: debug
    - tgt: '{{ first_control_node }}'  # Run on the first control node to test connectivity
    - stateful: True  # Store the result for conditional logic

# Debug admin.conf existence on first node
debug_admin_conf:
  cmd.run:
    - name: test -f /etc/kubernetes/admin.conf && echo "admin.conf exists" || echo "admin.conf missing"
    - output_loglevel: debug
    - tgt: '{{ first_control_node }}'

# Initialize the cluster if VIP is not reachable or not set
init_kubernetes_cluster:
  kubernetes.kubeadm_init:
    - name: init_cluster
    - pod_network_cidr: "10.244.0.0/16"
    - service_cidr: "10.96.0.0/12"
    - kubernetes_version: "v1.24.0"
    - control_plane_endpoint: "{{ vip if vip else first_control_node + ':6443' }}"  # Use VIP if available, else default to first node
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf
      - test -z "{{ vip }}" || test -n "{{ vip }}" && curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null 2>&1 || echo "unreachable" | grep -q "unreachable"
    - tgt: '{{ first_control_node }}'  # Target only the first control node for initialization
    - require:
      - sls: /formulas/common/k8s/install
      - sls: /formulas/common/k8s/configure

# Upload certificates for control plane joining (run on first control node after init)
upload_certs_and_get_key:
  kubernetes.kubeadm_upload_certs:
    - name: upload_certs
    - onlyif:
      - test -f /etc/kubernetes/admin.conf
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - onchanges:
      - kubernetes: init_kubernetes_cluster

# Create a token for joining nodes (run on first control node after init)
create_join_token:
  kubernetes.kubeadm_token_create:
    - name: create_token
    - ttl: "24h"  # Token time-to-live, adjust as needed
    - usages: ['signing', 'authentication']
    - onlyif:
      - test -f /etc/kubernetes/admin.conf
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - onchanges:
      - kubernetes: init_kubernetes_cluster

# Reset and join logic for additional control nodes if VIP is reachable
{% for node in control_nodes[1:] %}
reset_{{ node }}_if_needed:
  kubernetes.kubeadm_reset:
    - name: reset_{{ node }}
    - onlyif:
      - test -f /etc/kubernetes/admin.conf
      - test -n "{{ vip }}" && curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null 2>&1 && echo "reachable" || echo "unreachable" | grep -q "reachable"
    - tgt: '{{ node }}'  # Target specific control node for reset
    - require:
      - sls: /formulas/common/k8s/install
      - sls: /formulas/common/k8s/configure

join_{{ node }}_to_cluster:
  kubernetes.kubeadm_join:
    - name: join_cluster_{{ node }}
    - api_server_endpoint: "{{ vip if vip else first_control_node + ':6443' }}"
    - token: "{{ pillar.get('k8s_join_parameters', {}).get('token', salt['kubeadm.token_list'](tgt=first_control_node).get('tokens', [{}])[0].get('token', '')) }}"
    - discovery_token_ca_cert_hash: "{{ pillar.get('k8s_join_parameters', {}).get('discovery_token_ca_cert_hash', salt['kubernetes.kubeadm_cert_hash'](tgt=first_control_node)) }}"
    - certificate_key: "{{ pillar.get('k8s_join_parameters', {}).get('certificate_key', salt['kubernetes.kubeadm_certificate_key'](tgt=first_control_node)) }}"
    - control_plane: True  # Join as control plane node
    - onlyif:
      - test ! -f /etc/kubernetes/admin.conf
      - test -n "{{ vip }}" && curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null 2>&1 && echo "reachable" || echo "unreachable" | grep -q "reachable"
    - tgt: '{{ node }}'  # Target specific control node
    - require:
      - kubernetes: init_kubernetes_cluster
      - kubernetes: upload_certs_and_get_key
      - kubernetes: create_join_token
      - sls: /formulas/common/k8s/install
      - sls: /formulas/common/k8s/configure
    - onchanges:
      - kubernetes: reset_{{ node }}_if_needed
{% endfor %}