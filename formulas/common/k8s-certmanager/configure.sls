include:
  - /formulas/common/k8s-certmanager/install

{% set cert_manager_namespace = 'cert-manager' %}
{% set issuers = pillar.get('res-k8s:issuers') %}
# Loop through issuers defined in pillar data
{% for issuer_key, issuer in pillar['res-k8s']['issuers'].items() %}
ensure_{{ issuer.get('name', 'unknown-issuer') }}_issuer:
  k8s.certmanager_issuer_present:
    - namespace: {{ cert_manager_namespace }}
    - issuer_name: {{ issuer.get('name', 'unknown-issuer') }}
    - issuer_kind: {{ issuer.get('kind', 'Issuer') }}
    - spec: {{ issuer.get('spec', {}) | yaml }}
{% endfor %}

# Create a CA certificate using the self-signed issuer
ensure_cyberrange_ca:
  k8s.certmanager_certificate_present:
    - certificate_name: ca-cyberrange-cert
    - namespace: {{ cert_manager_namespace }}
    - secret_name: ca-cyberrange-secret
    - issuer_name: selfsigned-issuer
    - issuer_kind: ClusterIssuer
    - common_name: "CyberRange CA Certificate"
    - duration: 8760h  # 1 year
    - renew_before: 720h  # 30 days before expiry
    - is_ca: True

# Create a ClusterIssuer based on the CA certificate secret
ensure_cyberrange_ca_cluster_issuer:
  k8s.certmanager_issuer_present:
    - namespace: {{ cert_manager_namespace }}
    - issuer_name: cyberrange-ca-issuer
    - issuer_kind: ClusterIssuer
    - spec:
        ca:
          secretName: ca-cyberrange-secret
    - require:
      - k8s: ensure_cyberrange_ca

# bundles_present only accepts ConfigMap sources (no Secret sources), so
# copy the CA cert out of the Certificate's Secret into a ConfigMap first.
# Since ensure_cyberrange_ca sets is_ca: True, cert-manager populates a
# ca.crt key in ca-cyberrange-secret (identical to tls.crt, since this CA
# is self-signed).
ensure_cyberrange_ca_configmap:
  k8s.configmap_present:
    - namespace: {{ cert_manager_namespace }}
    - configmap_name: cyberrange-ca
    - data:
        ca.crt: {{ salt['kinetic_k8s.get_secret_value'](cert_manager_namespace, 'ca-cyberrange-secret', 'ca.crt', '') | yaml_dquote }}
    - require:
      - k8s: ensure_cyberrange_ca

# Distribute the CyberRange CA (plus trust-manager's default OS CA package)
# as a trusted bundle ConfigMap into every namespace, so workloads can
# verify certificates issued by cyberrange-ca-issuer without each namespace
# needing its own copy of the CA cert.
ensure_cyberrange_ca_bundle:
  k8s.bundles_present:
    - name: {{ pillar['res-k8s']['rsc-cert-ca']['name'] }}
    - sources:
      - config_map:
          name: cyberrange-ca
          key: ca.crt
      - use_default_cas: true
    - target_configmap_key: ca.crt
    - require:
      - k8s: ensure_cyberrange_ca_configmap
