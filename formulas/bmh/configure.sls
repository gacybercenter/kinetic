include:
- /formulas/bmh/install

# Ensure Helm is installed
helm_installed:
  cmd.run:
    - name: helm version --short
    - unless: test -f /usr/local/bin/helm

# Create namespace for GitLab (if it doesn't exist)
gitlab_namespace:
  cmd.run:
    - name: kubectl create namespace {{ pillar['gitlab_namespace'] }} --dry-run=client -o yaml | kubectl apply -f -
    - unless: kubectl get namespace {{ pillar['gitlab_namespace'] }}
    - require:
      - cmd: helm_installed

# Add GitLab Helm repository
gitlab_helm_repo:
  helm.repo_managed:
    - present:
      - name: gitlab
        url: {{ pillar['gitlab_helm_repo_url'] }}
    - require:
      - cmd: helm_installed

# Install or upgrade GitLab Helm release
gitlab_helm_release:
  helm.release_present:
    - name: {{ pillar['gitlab_release_name'] }}
    - chart: gitlab/gitlab
    - namespace: {{ pillar['gitlab_namespace'] }}
    - update: True
    - require:
      - helm: gitlab_helm_repo
      - cmd: gitlab_namespace