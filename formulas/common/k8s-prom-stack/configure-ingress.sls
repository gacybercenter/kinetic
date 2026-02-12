include:
- /formulas/common/k8s-certmanager/install

{% set ingress = pillar['kps-ingress'] %}

configure-issuer:
  kinetic-k8s.certmanager_issuer_present:
    - namespace: cluster-wide
    - issuer_name: cluster-issuer
    - issuer_kind: cluster-issuer

configure-ingress:
  kinetic-k8sk8s.ingress_present:
    - name: monitoring-ui
    - namespace: monitoring
    - hosts: {{ ingress['hosts'] }}
    - tls: {{ ingress['tls'] }}
    - ingress_class_name: traefik-internal
    - require:
      - configure-issuer

