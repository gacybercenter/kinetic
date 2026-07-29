include:
  - /formulas/common/k8s-typo3/install

{% set typo3 = pillar['res-k8s']['typo3'] %}
{% set route = typo3.get('values', {}).get('route', {}).get('main', {}) %}

{% if typo3['values']['route']['main']['enabled'] == true %}
typo3_main_httproute:
  k8s.httproute_present:
    - name: typo3-main
    - namespace: {{ typo3['namespace'] }}
    - parent_refs: {{ typo3['values']['route']['main']['parentRefs'] }}
    - rules:
      - matches: {{ typo3['values']['route']['main']['matches'] }}
        backendRefs:
          - name: typo3   # Service created by the Helm chart
            port: 8080
    - spec:
        hostnames: {{ typo3['values']['route']['main']['hostnames'] }}
{% endif %}
