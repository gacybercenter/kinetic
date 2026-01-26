# Include Helm installation formula to ensure Helm is available
include:
  - formulas.common.helm.install

# Add or update the Helm repository for OpenLDAP
add_openldap_repo:
  k8s_helm.helm_repo_present:
    - repo_name: helm-openldap
    - repo_url: https://jp-gouin.github.io/helm-openldap/
    - update_cache: True
    - require:
      - sls: formulas.common.helm.install

{% set ldap_lb_1 = pillar['ldap']['cert']['ip_addresses'][0] %}
{% set ldap_lb_2 = pillar['ldap']['cert']['ip_addresses'][1] %}

# Configure MetalLB pool and advertisement for internal IP
ensure_metallb_pool_ldap:
  k8s.metallb_pool_present:
    - namespace: unused-namespace
    - pool_name: ldap-lb-pool
    - addresses:
        - {{ ldap_lb_1 }}-{{ ldap_lb_2 }}
    - metallb_namespace: metallb-system

# Fetch additional configurable parameters from pillar with defaults
{% set ldap_namespace = pillar['ldap']['namespace'] %}
{% set ldap_version = pillar['ldap']['version'] %}
{% set ldap_admin_secret = pillar['ldap']['values']['global']['existingSecret'] %}
{% set ldap_values = pillar['ldap']['values'] %}
{% set ldap_pull_secret = pillar['ldap']['pull_secret'] %}

ensure_ldap_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar['ldap']['namespace'] }}

# Create Kubernetes pull secret for LDAP Helm chart repository
ensure_ldap_pull_secret:
  k8s.secret_present:
    - secret_name: {{ ldap_pull_secret.get('name', 'ldap-repo-secret') }}
    - namespace: {{ ldap_namespace }}
    - secret_type: kubernetes.io/dockerconfigjson
    - data:
        .dockerconfigjson: |
          {
            "auths": {
              "{{ ldap_pull_secret.get('repo', '') }}": {
                "username": "{{ ldap_pull_secret.get('user', 'build-token') }}",
                "password": "{{ ldap_pull_secret.get('key', '').strip() }}",
                "auth": "{{ (ldap_pull_secret.get('user', 'build-token') + ':' + ldap_pull_secret.get('key', '').strip()) | base64_encode }}"
              }
            }
          }
    - require:
      - k8s: ensure_ldap_namespace

# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ pillar['ldap']['cert']['name'] }}
    - certificate_name: {{ pillar['ldap']['cert']['name'] }}
    - namespace: {{ pillar['ldap']['cert']['namespace'] }}
    - secret_name: {{ pillar['ldap']['cert']['secret_name'] }}
    - issuer_name: {{ pillar['ldap']['cert']['issuer_name'] }}
    - issuer_kind: {{ pillar['ldap']['cert']['issuer_kind'] }}
    - common_name: {{ pillar['ldap']['cert']['common_name'] }}
    - dns_names: {{ pillar['ldap']['cert']['dns_names'] }}
    - ip_addresses: {{ pillar['ldap']['cert']['ip_addresses'] }}
    - duration: {{ pillar['ldap']['cert']['duration'] }}
    - renew_before: {{ pillar['ldap']['cert']['renew_before'] }}

# Ensure CA certificate file is present on the minion
ensure_config_ca_cert_file:
  file.managed:
    - name: /tmp/ca.pem
    - contents: {{ pillar['ldap']['cert']['ca'] | json }}
    - mode: 644
    - user: root
    - group: root
    - makedirs: True

# Create Kubernetes secret for LDAP admin credentials
ensure_ldap_admin_secret:
  k8s.secret_present:
    - secret_name: {{ ldap_admin_secret }}
    - namespace: {{ ldap_namespace }}
    - data:
        LDAP_ADMIN_PASSWORD: {{ pillar['admin-user']['password'] }}
        LDAP_CONFIG_ADMIN_PASSWORD: {{ pillar['admin-user']['password'] }}

# Install or upgrade OpenLDAP HA stack using Helm via k8s_helm state
install_openldap_ha:
  k8s_helm.helm_release_present:
    - release_name: openldap-ha
    - chart_name: helm-openldap/openldap-stack-ha
    - namespace: {{ ldap_namespace }}
    - values_dict: {{ ldap_values }}
    - version: {{ ldap_version }}
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - require:
      - k8s: ldap_tls_cert
      - k8s_helm: add_openldap_repo
