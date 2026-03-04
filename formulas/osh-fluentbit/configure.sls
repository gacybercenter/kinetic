include:
  - /formulas/osh-fluentbit/install
opensearch_env_secret:
  k8s.secret_present:
    - name: opensearch-env
    - secret_name: opensearch-env
    - namespace: openstack
    - secret_type: Opaque
    - data:
        {{ pillar['osh_values']['fluentd_env'] }}

install_fluentbit:
  k8s_helm.helm_release_present:
    - release_name: fluentbit
    - chart_name: openstack-helm/fluentbit
    - namespace: openstack
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - pillar_key: osh_values:fluentbit
    - set_values:
      - pods.env.fluentd.secrets={{ pillar['osh_values']['fluentd_env'] }}
    - require:
      - k8s: opensearch_env_secret
