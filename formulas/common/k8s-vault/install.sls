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

# Create namespace for Vault if specified
ensure_vault_namespace:
  k8s.namespace_present:
    - namespace: {{ vault_namespace }}

# Install Vault using Helm with pillar-driven values
install_vault:
  k8s_helm.helm_release_present:
    - release_name: vault
    - chart_name: hashicorp/vault
    - namespace: {{ vault_namespace }}
    - pillar_key: res-k8s:vault
    - version: {{ vault_version }}
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - require:
      - k8s: ensure_vault_namespace
      - k8s_helm: add_hashicorp_repo
      - cmd: update_helm_repos

# Note: The vault injector and other components will be enabled/disabled based on the pillar values under res-k8s:vault
