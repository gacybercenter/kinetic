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

# Step 1: Ensure Helm is installed on the target node
include:
  - /formulas/common/helm/install

# Step 2: Ensure the namespace exists
create_rook_namespace:
  k8s.namespace_present:
    - namespace: {{ namespace }}

# Step 3: Add the rook-ceph Helm repository
add_rook_helm_repo:
  helm.repo_managed:
    - present:
      - name: rook-release
        url: https://charts.rook.io/release
    - repo_update: True
    - namespace: {{ namespace }}
    - require:
      - k8s: create_rook_namespace

# Step 4: Render the values.yaml file from the template
render_rook_values_file:
  file.managed:
    - name: /tmp/rook-cluster-values.yaml
    - source: salt://formulas/common/k8s-rook/files/rook-cluster.j2
    - template: jinja
    - context:
        op_rook_namespace: "rook-ceph"
        cephClusterName: {{ namespace }}
        ceph_image: {{ ceph_image }}
        mgr_limits_memory: {{ limits_memory }}
        mgr_requests_cpu: {{ requests_cpu }}
        mgr_requests_memory: {{ requests_memory }}
        mon_limits_memory: {{ limits_memory }}
        mon_requests_cpu: {{ requests_cpu }}
        mon_requests_memory: {{ requests_memory }}
        osd_limits_memory: {{ limits_memory }}
        osd_requests_cpu: {{ requests_cpu }}
        osd_requests_memory: {{ requests_memory }}
        useAllNodes: false
        useAllDevices: false
        devices: {{ devices | default([]) }}
        enableCephFS: false
        enableRBD: true
        enableRGW: true
        dashboard_enabled: true
        dashboard_urlPrefix: "/"
        monitoring_enabled: true
        all_node_affinity_key: "role"
        all_node_affinity_operator: "In"
        all_node_affinity_value: {{ rook_role }}
        osd_node_affinity_key: "role"
        osd_node_affinity_operator: "In"
        osd_node_affinity_value: {{ rook_osd_role }}
    - require:
      - k8s: create_rook_namespace

# Step 5: Install or upgrade rook-ceph-cluster using Helm state with the values file
helm_install_rook_ceph_cluster:
  helm.release_present:
    - name: rook-ceph-release
    - chart: rook-release/rook-ceph-cluster
    - namespace: {{ namespace }}
    - version: {{ rook_version }}
    - flags:
      - dry-run
      - debug
    - values: /tmp/rook-cluster-values.yaml
    - require:
      - helm: add_rook_helm_repo
      - file: render_rook_values_file
      - k8s: create_rook_namespace