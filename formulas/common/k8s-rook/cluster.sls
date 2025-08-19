{% set devices = salt['pillar.get']('osd_mappings:storage:osd') %}
{% set namespace = pillar['rook']['namespace'] %}
{% set rook_version = pillar['rook']['rook_version'] %}
{% set ceph_image = pillar['rook']['ceph_image'] %}
{% set limits_cpu = pillar['rook']['resources']['limits']['cpu'] %}
{% set limits_memory = pillar['rook']['resources']['limits']['memory'] %}
{% set requests_cpu = pillar['rook']['resources']['requests']['cpu'] %}
{% set requests_memory = pillar['rook']['resources']['requests']['memory'] %}
{% set rook_role = pillar['rook']['mon']['node_role'] %}
{% set rook_osd_role = pillar['rook']['osd']['node_role'] %}

# Step 1: Ensure the namespace exists
create_rook_namespace:
  k8s.namespace_present:
    - namespace: {{ namespace }}

# Step 2: Ensure the Rook Ceph cluster is deployed using the CephCluster CRD
deploy_rook_ceph_cluster:
  k8s.ceph_cluster_present:
    - namespace: {{ namespace }}
    - cluster_name: rook-ceph
    - spec:
        cephVersion:
          image: {{ ceph_image }}
          allowUnsupported: false
        dataDirHostPath: /var/lib/rook
        mon:
          count: 3
          allowMultiplePerNode: false
        mgr:
          count: 2
          allowMultiplePerNode: false
        dashboard:
          enabled: true
          urlPrefix: "/"
          ssl: true
        monitoring:
          enabled: true
        placement:
          all:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                  - matchExpressions:
                    - key: ceph-type
                      operator: In
                      values:
                      - mon
          osd:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                  - matchExpressions:
                    - key: ceph-type
                      operator: In
                      values:
                      - osd
        resources:
          mgr:
            limits:
              memory: {{ limits_memory }}
            requests:
              cpu: {{ requests_cpu }}
              memory: {{ requests_memory }}
          mon:
            limits:
              memory: {{ limits_memory }}
            requests:
              cpu: {{ requests_cpu }}
              memory: {{ requests_memory }}
          osd:
            limits:
              memory: {{ limits_memory }}
            requests:
              cpu: {{ requests_cpu }}
              memory: {{ requests_memory }}
        storage:
          useAllNodes: false
          useAllDevices: false
          devices:
            {% if devices %}
            {% for device in devices %}
            - name: {{ device }}
            {% endfor %}
            {% else %}
            []
            {% endif %}
        enableCephFS: false
        enableRBD: true
        enableRGW: true
    - require:
      - k8s: create_rook_namespace