include:
  - /formulas/keystone/install
  - /formulas/osh-helm-repos/configure

keystone-admin:
  k8s.secret_present:
    - name: keystone-admin
    - namespace: openstack
    - data:
        username: {{ salt['pillar.get']('osh_users:keystone:user') }}
        password: {{ salt['pillar.get']('osh_users:keystone:password') }}
    - labels:
        app.kubernetes.io/managed-by: Helm
    - annotations:
        meta.helm.sh/release-name: keystone
        meta.helm.sh/release-namespace: openstack

install_keystone:
  k8s_helm.helm_release_present:
    - release_name: keystone
    - chart_name: openstack-helm/keystone
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: true
    - pillar_key: osh_values:keystone
    - require:
      - k8s: keystone-admin
