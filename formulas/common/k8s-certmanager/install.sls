certmanager_helm_repo:
  helm.repo_managed:
    - present:
      - name: jetstack
        url: https://charts.jetstack.io

certmanager_helm_install:
  helm.release_present:
    - name: cert-manager
    - namespace: cert-manager
    - chart: jetstack/cert-manager
    - flags:
      - create-namespace
      - crds.enabled=true