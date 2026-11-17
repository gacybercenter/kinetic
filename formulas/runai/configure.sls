include:
  - /formulas/runai/install

ensure_runai_repo:
  k8s_helm.helm_repo_present:
    - repo_name: runai
    - repo_url: https://helm.ngc.nvidia.com/nvidia/runai
    - username: "$oauthtoken"
    - password_pillar: res-k8s:gpu:runai:ngc_api_key
