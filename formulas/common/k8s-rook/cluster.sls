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

# Step 2: Add the rook-ceph Helm repository
add_rook_helm_repo:
  helm.repo_managed:
    - present:
      - name: rook-ceph
        url: https://charts.rook.io/release
        repo_update: True
        namespace: {{ namespace }}

# Step 3: Install or upgrade rook-ceph-cluster using Helm state with key-value flags
helm_install_rook_ceph_cluster:
  helm.release_present:
    - name: rook-ceph-cluster
    - chart: rook-ceph/rook-ceph-cluster
    - namespace: {{ namespace }}
    - version: {{ rook_version }}
    - flags:
      - dry-run
    - kvflags:
        - set: "cephVersion.image={{ ceph_image }}"
        - set: "cephClusterSpec.resources.limits.cpu={{ limits_cpu }}"
        - set: "cephClusterSpec.resources.limits.memory={{ limits_memory }}"
        - set: "cephClusterSpec.resources.requests.cpu={{ requests_cpu }}"
        - set: "cephClusterSpec.resources.requests.memory={{ requests_memory }}"
        - set: "cephClusterSpec.storage.useAllNodes=false"
        - set: "cephClusterSpec.storage.useAllDevices=false"
        {% if devices %}
        {% for device in devices %}
        - set: "cephClusterSpec.storage.devices[{{ loop.index0 }}].name={{ device }}"
        {% endfor %}
        {% else %}
        - set: "cephClusterSpec.storage.devices=[]"
        {% endif %}
        - set: "cephClusterSpec.enableCephFS=false"
        - set: "cephClusterSpec.enableRBD=true"
        - set: "cephClusterSpec.enableRGW=true"
        - set: "cephClusterSpec.dashboard.enabled=true"
        - set: "cephClusterSpec.dashboard.urlPrefix=/"
        - set: "cephClusterSpec.monitoring.enabled=true"
        - set: "cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=role"
        - set: "cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In"
        - set: "cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]={{ rook_role }}"
        - set: "cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=role"
        - set: "cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In"
        - set: "cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]={{ rook_osd_role }}"