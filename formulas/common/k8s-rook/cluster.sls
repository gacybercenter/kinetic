{% set devices = pillar['osd_mappings']['storage']['osd'] %}
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
        # Core Rook Ceph Cluster settings (adjust as needed based on your requirements)
        cephClusterSpec.image: {{ ceph_image }}
        cephClusterSpec.resources.limits.cpu: {{ limits_cpu }}
        cephClusterSpec.resources.limits.memory: {{ limits_memory }}
        cephClusterSpec.resources.requests.cpu: {{ requests_cpu }}
        cephClusterSpec.resources.requests.memory: {{ requests_memory }}
        cephClusterSpec.storage.useAllNodes: "false"
        cephClusterSpec.storage.useAllDevices: "false"
        # Explicitly specify disks for OSDs from pillar data
        {% if devices %}
        {% for device in devices %}
        cephClusterSpec.storage.devices[{{ loop.index0 }}].name: "{{ device }}"
        {% endfor %}
        {% else %}
        # Fallback to an empty list if no devices are provided
        cephClusterSpec.storage.devices: []
        {% endif %}
        # Enable specific Ceph features (based on values.yaml defaults)
        cephClusterSpec.enableCephFS: "false"
        cephClusterSpec.enableRBD: "true"
        cephClusterSpec.enableRGW: "true"
        # Dashboard settings
        cephClusterSpec.dashboard.enabled: "true"
        cephClusterSpec.dashboard.urlPrefix: "/"
        # Monitoring settings
        cephClusterSpec.monitoring.enabled: "true"
        # Node selection for general components (optional, can be customized via pillar if needed)
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key: "role"
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator: "In"
        cephClusterSpec.placement.all.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]: {{ rook_role }}
        # Node selection specifically for OSDs to target rook-osd-node role
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key: "role"
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator: "In"
        cephClusterSpec.placement.osd.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]: {{ rook_osd_role }}