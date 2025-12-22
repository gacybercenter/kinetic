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
{% set ldap_values = pillar['ldap']['values'] %}

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
