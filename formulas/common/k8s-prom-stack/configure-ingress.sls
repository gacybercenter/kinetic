include:
- /formulas/common/k8s-prom-stack/ingress
- /formulas/common/k8s-certmanager/install

{% set host = pillar['kps-ingress-host'] %}

configure-issuer:
  kinetic_k8s.certmanager_issuer_present:
    - namespace: monitoring
    - issuer_name: selfsigned
    - spec:
      selfSigned: {}

configure-ingress:
  k8s_helm.helm_repo_present:
    - name: monitoring-ui
    - namespace: monitoring
    - hosts: host
    - tls:
      - secretName: prom-ssc-tls
        hosts: 
          - metrics-dev.internal.gacyberrange.org
    - require:
      - configure-issuer

