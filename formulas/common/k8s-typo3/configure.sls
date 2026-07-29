include:
  - /formulas/common/k8s-typo3/install

{% set typo3 = pillar.get('res-k8s:typo3', {}) %}
{% set route = typo3.get('values', {}).get('route', {}).get('main', {}) %}

{% if route.get('enabled', False) %}
typo3_main_httproute:
  k8s.httproute_present:
    - name: typo3-main
    - namespace: {{ typo3.get('namespace', 'typo3') }}
    - parent_refs: {{ route.get('parentRefs', []) }}
    - rules:
      - matches: {{ route.get('matches', []) }}
        backendRefs:
          - name: typo3   # Service created by the Helm chart
            port: 8080
    - spec:
        hostnames: {{ route.get('hostnames', []) }}
{% endif %}
