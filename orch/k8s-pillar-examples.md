res-k8s:
  vip: 10.150.1.61
  k8s_nodes:
    - master-rsc-0
    - master-rsc-1
    - master-rsc-2

#node pillars:
bmh:
  master-rsc-2:
...
    k8s_control_plane: true
