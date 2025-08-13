rook-cluster-{{ node }}:
  file.managed:
    - name: /tmp/rook-cluster-{{ node }}.yaml
    - source: salt://formulas/common/k8s-rook/files/rook-cluster.j2
    - template: jinja