include:
- /formulas/common/k8s-certmanager/install

{% set host = pillar['kps-ingress-host'] %}

configure-issuer:
  kinetic_k8s.certmanager_issuer_present:
    - namespace: monitoring
    - issuer_name: selfsigned
    - spec:
      selfSigned: {}

configure-ingress:
  kinetic_k8s.ingress_present:
    - name: monitoring-ui
    - namespace: monitoring
    - hosts: {{ host }}
    - tls:
      - secretName: prom-ssc-tls
        hosts: 
          - metrics-dev.internal.gacyberrange.org
    - ingress_class_name: traefik-internal
    - require:
      - configure-issuer

