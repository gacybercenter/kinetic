# Orchestration script to deploy kube-vip and bootstrap a High Availability Kubernetes cluster
# Dynamically pulls VIP and control nodes from pillar data

# Fetch pillar data for the 'bmo' minion
{% set pillardata = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': 'bmo'}) %}
# Get VIP and nodes from pillar data with safer handling
{% set res_k8s = pillardata['res-k8s'] %}
{% set vip = res_k8s.get('vip', '') %}
{% set k8s_nodes = res_k8s.get('k8s_nodes', ['master-rsc-0']) %}
{% set interface = res_k8s.get('vip-interface', 'eth0') %}  # Default to 'eth0' if not specified in pillar
{% set oidc_issuer = res_k8s.get('oidc-issuer', res_k8s.get('oidc_issuer', '')) %}
{% set kube_vip_version = 'v0.8.3' %}  # Check for the latest version at https://github.com/kube-vip/kube-vip/releases

# Find the first node with k8s_control_plane == true
{% set first_control_node = '' %}
{% for node in k8s_nodes %}
  {% set node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': node}) %}
  {% if node_pillar.get('k8s_control_plane', False) == True and first_control_node == '' %}
    {% set first_control_node = node %}
  {% endif %}
{% endfor %}
# Fallback to the first node in the list if no control plane node is found
{% if first_control_node == '' %}
  {% set first_control_node = k8s_nodes[0] if k8s_nodes else 'master-rsc-0' %}
{% endif %}
{% set first_node_pillar = salt.saltutil.runner('pillar.show_pillar', kwarg={'minion': first_control_node}) %}
{% set kubeconfig_src = first_node_pillar.get('kubernetes', {}).get('kubeconfig', '/etc/kubernetes/admin.conf') %}

# Debug pillar data to ensure it's available
debug_pillar_data:
  cmd.run:
    - name: echo "VIP {{ vip }}, K8s Nodes {{ k8s_nodes }}, First Control Node {{ first_control_node }}, Interface {{ interface }}"
    - tgt: '*'
    - output_loglevel: debug

# Step 1: Ensure Kubernetes dependencies are installed on the first control plane node
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
    - require:
      - salt: pull_kube_vip_image

# Step 6: Initialize Kubernetes cluster on the first control node with VIP as control-plane-endpoint
init_kubernetes_cluster:
  salt.function:
    - name: kubeadm.init
    - kwarg:
        pod_network_cidr: "10.244.0.0/16"
        service_cidr: "10.96.0.0/12"
        kubernetes_version: "v1.34.9"
        cri_socket: unix:///var/run/crio/crio.sock
        control_plane_endpoint: "{{ vip }}:6443"  # Use VIP for HA control plane
    - unless:
      - curl -k --connect-timeout 5 https://{{ vip }}:6443 >/dev/null
    - tgt: '{{ first_control_node }}'  # Target only the first control node for initialization

# Step 6.1: Set a grain on the first control node to mark it as bootstrapped
set_bootstrap_grain:
  salt.function:
    - name: grains.setval
    - kwarg:
        key: k8s_bootstrapped
        val: true
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - require:
      - salt: init_kubernetes_cluster

# Step 6.2: Sync grains to ensure the new grain is available
sync_grains:
  salt.function:
    - name: saltutil.refresh_grains
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - require:
      - salt: set_bootstrap_grain

# Step 7: Upload certificates for control plane joining (run on first control node after init)
upload_certs:
  salt.function:
    - name: kubeadm.upload_certs
    - onlyif:
      - test -f /etc/kubernetes/admin.conf  # Only run if cluster is initialized
    - tgt: '{{ first_control_node }}'  # Run only on the initialized node
    - watch:
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

# kubectl / Helm on this node (Cilium, later formulas) expect the
# admin kubeconfig at /root/.kube/config. Source path is pillar
# kubernetes.kubeconfig (defaults to /etc/kubernetes/admin.conf).
setup_root_kubeconfig:
  salt.function:
    - name: cmd.run
    - tgt: '{{ first_control_node }}'
    - kwarg:
        cmd: |
          mkdir -p /root/.kube &&
          cp {{ kubeconfig_src }} /root/.kube/config &&
          chmod 600 /root/.kube/config &&
          chown root:root /root/.kube/config
        onlyif: test -f {{ kubeconfig_src }}
    - require:
      - salt: init_kubernetes_cluster

{# kubeadm.init does not take apiServer extraArgs. Patch the static pod so
   OIDC works on first boot and on re-run (init is skipped once VIP:6443 is
   up). --oidc-groups-prefix=- matches username: a bare flag is invalid. #}
{% if oidc_issuer %}
configure_apiserver_oidc:
  salt.function:
    - name: cmd.run
    - tgt: '{{ first_control_node }}'
    - kwarg:
        cmd: |
          python3 - <<'PY'
          import pathlib
          import re
          path = pathlib.Path("/etc/kubernetes/manifests/kube-apiserver.yaml")
          text = path.read_text()
          flags = {
              "oidc-issuer-url": "{{ oidc_issuer }}",
              "oidc-client-id": "kubernetes",
              "oidc-username-claim": "preferred_username",
              "oidc-groups-claim": "groups",
              "oidc-username-prefix": "-",
              "oidc-groups-prefix": "-",
          }
          lines = text.splitlines()
          seen = set()
          out = []
          oidc_re = re.compile(r"^(\s*)-\s+--oidc-([a-z0-9-]+)(?:=.*)?\s*$")
          kube_re = re.compile(r"^(\s*)-\s+kube-apiserver\s*$")
          for line in lines:
              m = oidc_re.match(line)
              if m and m.group(2) in flags:
                  indent, key = m.group(1), m.group(2)
                  out.append(f"{indent}- --oidc-{key}={flags[key]}")
                  seen.add(key)
                  continue
              out.append(line)
          if set(flags) - seen:
              final = []
              for line in out:
                  final.append(line)
                  m = kube_re.match(line)
                  if m:
                      indent = m.group(1)
                      for key, value in flags.items():
                          if key not in seen:
                              final.append(f"{indent}- --oidc-{key}={value}")
                              seen.add(key)
              out = final
          missing = set(flags) - seen
          if missing:
              raise SystemExit(f"could not insert OIDC flags {sorted(missing)}")
          new = "\n".join(out) + "\n"
          if new != text:
              path.write_text(new)
              print("patched kube-apiserver OIDC flags")
          else:
              print("kube-apiserver OIDC flags already present")
          PY
        onlyif: test -f /etc/kubernetes/manifests/kube-apiserver.yaml
    - require:
      - salt: init_kubernetes_cluster
      - salt: setup_root_kubeconfig
{% endif %}

k8s_cilium:
  salt.state:
    - tgt: '{{ first_control_node }}'
    - sls: /formulas/common/k8s-cilium
    - require:
      - salt: setup_root_kubeconfig
{%- if oidc_issuer %}
      - salt: configure_apiserver_oidc
{%- endif %}
