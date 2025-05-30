certmanager_helm_repo:
  helm.repo_managed:
    - present:
      - name: jetstack
        url: https://charts.jetstack.io

certmanager_helm_install:
  helm.release_present:
    - name: cert-manager
    - namespace: cert-manager
    - chat: certname/jetstack
    - kvglags:
        create-namespace