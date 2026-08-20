include:
  - /formulas/keycloak/install
  - /formulas/keycloak/realms

{% if pillar.get('ldap', {}).get('logger-cm') %}
{% set cm = pillar['res-k8s']['logger-kc-cm'] %}
ensure_ldap_fluentbit_configmap:
  k8s.configmap_present:
    - name: {{ cm['name'] }}
    - configmap_name: {{ cm['name'] }}
    - namespace: {{ ldap_namespace }}
    - data: {{ cm['data'] | yaml }}
{% endif %}
