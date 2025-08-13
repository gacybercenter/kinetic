calico_values:
  file.managed:
    - name: /tmp/calico.yaml
    - source: salt://formulas/common/k8s-calico/files/calico-values.j2
    - template: jinja
helm_calico_repo:
  helm.repo_managed:
    - present:
      - name: calico
        url: https://docs.tigera.io/calico/charts 
        repo_update: true
        namespace: tigera-operator

helm_calico_release:
  helm.release_present:
    - name: calico
    - chart: calico/tigera-operator
    - namespace: tigera-operator
    - kvflags:
        values: /tmp/calico.yaml
    - unless: helm list -n tigera-operator |grep calico
    - require:
      - file: calico_values
    - watch:
      - file: calico_values