# Setup the Kubernetes repo
kube.repo:
  pkgrepo.managed:
    - name: {{ pillar['k8s_repo'] }}
    - file: {{ pillar['k8s_source_file'] }}
    - key_url: {{ pillar['k8s_gpg_key'] }}
crio_repo:
  pkgrepo.managed:
    - name: {{ pillar['crio_repo'] }}
    - file: {{ pillar['crio_source_file'] }}
    - key_url: {{ pillar['crio_gpg_key'] }}

# Install Kubernetes
kube.packages:
  pkg.installed:
    - hold: True
    - pkgs:
      - kubelet
      - kubeadm
      - kubectl
      - ca-certificates
      - curl
      - apt-transport-https
      - gpg
      - make
      - cri-o