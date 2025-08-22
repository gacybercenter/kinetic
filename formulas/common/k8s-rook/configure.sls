include:
  - /formulas/common/k8s-rook/install

rook_values:
  file.managed:
    - name: /tmp/rook.yaml
    - source: salt://formulas/common/k8s-rook/files/rook-values.j2
    - template: jinja
helm_rook_repo:
  helm.repo_managed:
    - present:
      - name: rook-release
        url: https://charts.rook.io/release
        repo_update: true
        namespace: rsc-ceph

helm_rook_release:
  helm.release_present:
    - name: rook-ceph
    - chart: rook-release/rook-ceph
    - namespace: rsc-ceph
    - kvflags:
        values: /tmp/rook.yaml
    - unless: helm list -n rook-ceph |grep rook
    - require:
      - file: rook_values
    - watch:
      - file: rook_values