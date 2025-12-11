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

# Manage Certificate for TLS using certmanager_certificate_present from k8s.py, with pillar-driven values
ldap_tls_cert:
  k8s.certmanager_certificate_present:
    - name: {{ pillar.get('ldap:cert:name', 'ldap-tls-cert') }}
    - namespace: {{ pillar.get('ldap:cert:namespace', 'openldap-ha') }}
    - secret_name: {{ pillar.get('ldap:cert:secret_name', 'tls-cert') }}
    - issuer_name: {{ pillar.get('ldap:cert:issuer_name', 'selfsigned-issuer') }}
    - issuer_kind: {{ pillar.get('ldap:cert:issuer_kind', 'ClusterIssuer') }}
    - common_name: {{ pillar.get('ldap:cert:common_name', 'ldap.dev-gacyberrange.org') }}
    - dns_names: {{ pillar.get('ldap:cert:dns_names', [
        'ldap.dev-gacyberrange.org',
        'my-openldap-ha-openldap.openldap-ha.svc',
        'my-openldap-ha-openldap.openldap-ha.svc.cluster.local',
        'localhost',
        '127.0.0.1'
      ]) }}
    - ip_addresses: {{ pillar.get('ldap:cert:ip_addresses', ['127.0.0.1']) }}
    - duration: {{ pillar.get('ldap:cert:duration', '2160h') }}
    - renew_before: {{ pillar.get('ldap:cert:renew_before', '360h') }}
    - require:
      - k8s_helm: install_openldap_ha
