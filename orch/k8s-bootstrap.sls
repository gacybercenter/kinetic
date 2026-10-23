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

# Step 2: Pull kube-vip into containerd so `ctr run` can render the manifest.
# kubeadm init uses CRI-O, so this image is not what the static pod runs from.
pull_kube_vip_image:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: ctr image pull ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
        onlyif: test ! -f /etc/kubernetes/manifests/kube-vip.yaml
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

# kubelet static pods use CRI-O after kubeadm init, not the containerd
# `ctr run` used to render the manifest. Pull into CRI-O and touch the
# manifest so kubelet (re)starts kube-vip.
ensure_kube_vip_crio:
  salt.function:
    - name: cmd.run
    - tgt: '{{ first_control_node }}'
    - kwarg:
        cmd: |
          crictl pull ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
          touch /etc/kubernetes/manifests/kube-vip.yaml
        onlyif: test -f /etc/kubernetes/manifests/kube-vip.yaml && test -S /var/run/crio/crio.sock
    - require:
      - salt: init_kubernetes_cluster
      - salt: generate_kube_vip_manifest

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

{# Kubernetes 1.32+ removed --oidc-* from kube-apiserver. 1.34 needs
   Structured Authentication Configuration (--authentication-config).
   kubeadm.init still has no extraArgs path, so patch the static pod. #}
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

          issuer = "{{ oidc_issuer }}"
          auth_file = pathlib.Path("/etc/kubernetes/auth-config.yaml")
          manifest = pathlib.Path("/etc/kubernetes/manifests/kube-apiserver.yaml")
          auth_file.write_text(
              "apiVersion: apiserver.config.k8s.io/v1\n"
              "kind: AuthenticationConfiguration\n"
              "jwt:\n"
              "- issuer:\n"
              f"    url: {issuer}\n"
              "    audiences:\n"
              "    - kubernetes\n"
              "  claimMappings:\n"
              "    username:\n"
              "      claim: preferred_username\n"
              '      prefix: ""\n'
              "    groups:\n"
              "      claim: groups\n"
              '      prefix: ""\n'
          )
          orig = manifest.read_text()
          lines = [ln for ln in orig.splitlines() if "--oidc-" not in ln]

          def indent_of(line):
              return re.match(r"^[ \t]*", line).group(0)

          def insert_after_key(lines, key, block_lines):
              key_re = re.compile(r"^([ \t]*)" + re.escape(key) + r":\s*$")
              for i, ln in enumerate(lines):
                  m = key_re.match(ln)
                  if not m:
                      continue
                  ind = m.group(1)
                  extra = [ind + x for x in block_lines]
                  return lines[: i + 1] + extra + lines[i + 1 :]
              raise SystemExit("could not find %s in kube-apiserver manifest" % key)

          if not any("--authentication-config" in ln for ln in lines):
              kube_re = re.compile(r"^([ \t]*)-\s+kube-apiserver\s*$")
              inserted = False
              out = []
              for ln in lines:
                  out.append(ln)
                  m = kube_re.match(ln)
                  if m and not inserted:
                      out.append(
                          m.group(1)
                          + "- --authentication-config=/etc/kubernetes/auth-config.yaml"
                      )
                      inserted = True
              if not inserted:
                  raise SystemExit("could not find kube-apiserver command")
              lines = out

          joined = "\n".join(lines)
          if "name: auth-config" not in joined:
              lines = insert_after_key(
                  lines,
                  "volumeMounts",
                  [
                      "- mountPath: /etc/kubernetes/auth-config.yaml",
                      "  name: auth-config",
                      "  readOnly: true",
                  ],
              )
              lines = insert_after_key(
                  lines,
                  "volumes",
                  [
                      "- name: auth-config",
                      "  hostPath:",
                      "    path: /etc/kubernetes/auth-config.yaml",
                      "    type: File",
                  ],
              )

          new = "\n".join(lines) + "\n"
          if new != orig:
              manifest.write_text(new)
              print("patched kube-apiserver structured OIDC auth")
          else:
              print("kube-apiserver structured OIDC auth already present")
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
