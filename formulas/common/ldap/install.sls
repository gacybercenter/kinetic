# Install OpenLDAP-HA using modern k8s_helm states

include:
  - /formulas/common/helm/install

# Ensure Helm is available
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

# Add OpenLDAP Helm repository
add_openldap_repo:
  k8s_helm.helm_repo_present:
    - repo_name: helm-openldap
    - repo_url: https://jp-gouin.github.io/helm-openldap/
    - require:
      - test: helm_installed

# Update Helm repositories
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - k8s_helm: add_openldap_repo

# Define variables from pillar
{% set ldap_namespace = pillar['ldap']['namespace'] %}
{% set ldap_version = pillar['ldap']['version'] %}
{% set ldap_admin_secret = pillar['ldap']['values']['global']['existingSecret'] %}
{% set ldap_pull_secret = pillar['ldap']['pull_secret'] %}

# Create namespace for LDAP
ensure_ldap_namespace:
  k8s.namespace_present:
    - namespace: {{ ldap_namespace }}

# Create Kubernetes pull secret for LDAP container images
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

# Create TLS certificate for LDAP using the new certs structure
{% set cert = pillar['ldap']['cert'] %}
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ cert['name'] }}
    - namespace: {{ cert['namespace'] }}
    - certificate_name: {{ cert['name'] }}
    - secret_name: {{ cert['secret_name'] }}
    - issuer_name: {{ cert['issuer'] }}
    - issuer_kind: {{ cert['issuer_kind'] }}
    - common_name: {{ cert['commonname'] }}
    - dns_names: {{ cert['dns_names'] | default([]) }}
    - ip_addresses: {{ pillar['ldap']['cert']['ip_addresses'] | default([]) }}
    - duration: 2160h
    - renew_before: 360h
    - require:
      - k8s: ensure_ldap_namespace

# Create admin credentials secret
ensure_ldap_admin_secret:
  k8s.secret_present:
    - secret_name: {{ ldap_admin_secret }}
    - namespace: {{ ldap_namespace }}
    - data:
        LDAP_ADMIN_PASSWORD: {{ pillar['ldap']['admin-user']['password'] | string }}
        LDAP_CONFIG_ADMIN_PASSWORD: {{ pillar['ldap']['admin-user']['password'] | string }}
    - require:
      - k8s: ldap_tls_cert

# Create OpenSearch/FluentBit credentials secret (if configured)
{% if pillar.get('opensearch_fluentbit_username') %}
ensure_fluentbit_user_secret:
  k8s.secret_present:
    - secret_name: fluentbit-creds
    - namespace: {{ ldap_namespace }}
    - data:
        OPENSEARCH_USERNAME: {{ pillar['opensearch_fluentbit_username'] }}
        OPENSEARCH_PASSWORD: {{ pillar['opensearch_fluentbit_password'] }}
    - require:
      - k8s: ensure_ldap_admin_secret
{% endif %}

# Create ConfigMap for FluentBit LDAP logging (if configured)
{% if pillar.get('ldap', {}).get('logger-cm') %}
{% set cm = pillar['ldap']['logger-cm'] %}
ensure_ldap_fluentbit_configmap:
  k8s.configmap_present:
    - name: {{ cm['name'] }}
    - configmap_name: {{ cm['name'] }}
    - namespace: {{ ldap_namespace }}
    - data: {{ cm['data'] | yaml }}
    - require:
      - k8s: ensure_fluentbit_user_secret
{% endif %}

# Install OpenLDAP HA stack using modern k8s_helm state
install_openldap_ha:
  k8s_helm.helm_release_present:
    - release_name: openldap-ha
    - chart_name: helm-openldap/openldap-stack-ha
    - namespace: {{ ldap_namespace }}
    - pillar_key: ldap:values
    - version: {{ ldap_version }}
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - require:
      - k8s: ldap_tls_cert
      - k8s_helm: add_openldap_repo
      - cmd: update_helm_repos
{% if pillar.get('ldap', {}).get('logger-cm') %}
      - k8s: ensure_ldap_fluentbit_configmap
{% endif %}
