include:
  - /formulas/keycloak/install
  - /formulas/keycloak/realms

{% set cm = pillar['res-k8s']['logger-kc-cm'] %}
ensure_ldap_fluentbit_configmap:
  k8s.configmap_present:
    - name: {{ cm['name'] }}
    - configmap_name: {{ cm['name'] }}
    - namespace: keycloak
    - data: {{ cm['data'] | yaml }}
