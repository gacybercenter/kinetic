include:
  - /formulas/osh-rabbitmq/install
  - /formulas/osh-helm-repos/configure

install_rabbitmq:
  k8s_helm.helm_release_present:
    - release_name: rabbitmq
    - chart_name: openstack-helm/rabbitmq
    - namespace: openstack
    - wait_timeout: 600
    - wait_interval: 10
    - values_dict:
        pod:
          replicas:
            server: 1
        images:
          tags:
            prometheus_rabbitmq_exporter_helm_tests: {{ pillar['osh_values']['rabbitmq']['images']['tags']['prometheus_rabbitmq_exporter_helm_tests'] }}
            rabbitmq_init: {{ pillar['osh_values']['rabbitmq']['images']['tags']['rabbitmq_init'] }}
    - require:
      - sls: /formulas/osh-rabbitmq/install
      - sls: /formulas/osh-helm-repos/configure