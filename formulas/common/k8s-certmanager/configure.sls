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
