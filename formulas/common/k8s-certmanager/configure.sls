include: 
  - /formulas/common/k8s-certmanager/install

{% set cert_manager_namespace = 'cert-manager' %}

# Loop through issuers defined in pillar data
{% for issuer_key, issuer in pillar.get('res-k8s:issuers', {}).items() %}
ensure_{{ issuer.get('name', 'unknown-issuer') }}_issuer:
  k8s.certmanager_issuer_present:
    - namespace: {{ cert_manager_namespace }}
    - issuer_name: {{ issuer.get('name', 'unknown-issuer') }}
    - issuer_kind: {{ issuer.get('kind', 'Issuer') }}
    - spec: {{ issuer.get('spec', {}) | yaml }}
{% endfor %}