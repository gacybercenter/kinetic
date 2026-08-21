add_typo3_repo:
  k8s_helm.helm_repo_present:
    - repo_name: christianhuth
    - repo_url: https://charts.christianhuth.de

# Install typo3 Operator
typo3_install:
  k8s_helm.helm_release_present:
    - release_name: typo3
    - chart_name: christianhuth/typo3
    - namespace: {{ pillar['res-k8s']['typo3']['namespace'] }}
    - pillar_key: res-k8s:typo3:values
    - wait_timeout: 300
    - require:
      - k8s_helm: add_typo3_repo
