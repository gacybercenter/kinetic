include:
  - /formulas/common/k8s-prom-stack/configure-ingress
add_kube_prom_stack_repo:
  kinetic-helm.helm_repo_present:
    - repo_name: prometheus-community
    - repo_url: https://prometheus-community.github.io/helm-charts
add_kube_prom_stack_release:
  kinetic-helm.helm_release_present:
    - relase_name: kube-prom-stack
    - chart_name: prometheus-community/kube-prometheus-stack
    - namespace: monitoring
    - pillar_key: kps-values

