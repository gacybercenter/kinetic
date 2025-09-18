{% set k8s = salt['pillar.get']('k8s') %}
{% set opensearch_index_name = salt['pillar.get']('index') %}

configure_opensearch_for_logging:
  salt.state:
    - tgt: {{ k8s }}
    - sls:
      - formulas.k8s-logger.configure
    - pillar:
        opensearch_admin_user: {{ pillar.get('opensearch_admin_user', 'admin') }}
        fluentd_password: {{ pillar.get('fluentd_password', '') }}
        opensearch_host: {{ pillar.get('opensearch_host', 'https://api.logger.services.gacyberrange.org:443') }}
        opensearch_index_name: {{ opensearch_index_name }}
        opensearch_role_name: {{ opensearch_index_name}}_role
        opensearch_user_name: {{ pillar.get('opensearch_user_name', 'fluentbit') }}
        opensearch_shards: {{ pillar.get('opensearch_shards', 1) }}
        opensearch_replicas: {{ pillar.get('opensearch_replicas', 1) }}