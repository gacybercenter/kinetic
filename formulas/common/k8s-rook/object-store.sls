{# CephObjectStore with RGW STS (and IAM, for OIDC provider + roles).
   Pillar:
     res-k8s:rook:object_store:
       name: my-store
       gateway_instances: 2
       erasure_coded:
         data_chunks: 2
         coding_chunks: 1
       sts_key: "<same 16+ char key on every RGW>"
         # ceph-authtool --gen-print-key
#}
{% set store = pillar['res-k8s']['rook']['object_store'] %}
{% set ec = store.get('erasure_coded', {'data_chunks': 2, 'coding_chunks': 1}) %}

rook_ceph_object_store:
  rook.ceph_object_store_present:
    - name: {{ store.get('name', 'my-store') }}
    - namespace: {{ pillar['res-k8s']['rook'].get('namespace', 'rook-ceph') }}
    - replicas: {{ store.get('metadata_replicas', 3) }}
    - port: {{ store.get('port', 80) }}
    - ssl_enabled: false
    - gateway_instances: {{ store.get('gateway_instances', 2) }}
    - enable_swift_api: false
    - enable_s3_api: true
    - preserve_pools_on_delete: true
    - erasure_coded: {{ ec | tojson }}
    - enable_sts: true
    - sts_key: {{ store['sts_key'] | yaml_dquote }}
    - enable_apis: {{ store.get('enable_apis', ['s3', 's3website', 'sts', 'iam', 'notifications']) | tojson }}
    - rgw_config:
        rgw_s3_auth_use_sts: "true"
        rgw_sts_key: {{ store['sts_key'] | yaml_dquote }}
