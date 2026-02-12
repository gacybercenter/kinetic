include:
- /formulas/common/k8s-certmanager/install

{% set ingress = pillar['kps-ingress'] %}

configure-issuer:
  k8s.certmanager_issuer_present:
    - namespace: cluster-wide
    - issuer_name: cluster-issuer
    - issuer_kind: ClusterIssuer

configure-ingress:
  k8s.ingress_present:
    - name: monitoring-ui
    - namespace: monitoring
    - hosts: {{ ingress['hosts'] }}
    - tls: {{ ingress['tls'] }}
    - ingress_class_name: traefik-internal
    - require:
      - configure-issuer

