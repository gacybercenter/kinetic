include:
  - /formulas/common/helm

# Add HashiCorp Helm repository for Vault
add_hashicorp_repo:
  k8s_helm.helm_repo_present:
    - repo_name: hashicorp
    - repo_url: https://helm.releases.hashicorp.com

# Update Helm repositories
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - k8s_helm: add_hashicorp_repo

# Define variables from pillar
{% set vault_namespace = pillar['res-k8s']['vault']['global']['namespace'] %}
{% set vault_version = pillar['res-k8s']['vault']['version'] %}
{% set vault_nodes = pillar['res-k8s']['vault']['nodes'] %}
{% set issuer = "cyberrange-ca-issuer" %}
# Create namespace for Vault if specified
ensure_vault_namespace:
  k8s.namespace_present:
    - namespace: {{ vault_namespace }}
# Create certificates for each Vault node

vault_cert:
  k8s.certmanager_certificate_present:
    - name: vault-transport-cert
    - namespace: {{ vault_namespace }}
    - certificate_name: vault-transport-cert
    - secret_name: vault-transport-tls
    - issuer_name: {{ issuer }}
    - issuer_kind: ClusterIssuer
    - common_name: vault.{{ vault_namespace }}.svc.cluster.local
    - dns_names:
      # Individual pods
      {% for node in vault_nodes %}
      - {{ node }}
      - {{ node }}.vault-internal
      - {{ node }}.{{ vault_namespace }}
      - {{ node }}.{{ vault_namespace }}.svc
      - {{ node }}.{{ vault_namespace }}.svc.cluster.local
      {% endfor %}
      # Services
      - vault
      - vault.{{ vault_namespace }}
      - vault.{{ vault_namespace }}.svc
      - vault.{{ vault_namespace }}.svc.cluster.local
      # Headless service (very important for Raft)
      - vault-internal
      - vault-internal.{{ vault_namespace }}
      - vault-internal.{{ vault_namespace }}.svc
      - vault-internal.{{ vault_namespace }}.svc.cluster.local
    - duration: 8760h    # 1 year
    - renew_before: 720h # 30 days
    - require:
      - k8s: ensure_vault_namespace

# Install Vault using Helm with pillar-driven values
install_vault:
  k8s_helm.helm_release_present:
    - release_name: vault
    - chart_name: hashicorp/vault
    - namespace: {{ vault_namespace }}
    - pillar_key: res-k8s:vault
    - set_values:
      - image.tag=latest
    - version: {{ vault_version }}
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - require:
      - k8s: ensure_vault_namespace
      - k8s_helm: add_hashicorp_repo
      - cmd: update_helm_repos

# Note: The vault injector and other components will be enabled/disabled based on the pillar values under res-k8s:vault
