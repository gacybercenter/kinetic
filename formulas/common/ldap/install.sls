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

# Fetch additional configurable parameters from pillar with defaults
{% set ldap_namespace = pillar.get('ldap:namespace', 'ldap') %}
{% set ldap_version = pillar.get('ldap:version', '4.3.3') %}

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
    - keep_values_file: False
    - require:
      - k8s_helm: add_openldap_repo
