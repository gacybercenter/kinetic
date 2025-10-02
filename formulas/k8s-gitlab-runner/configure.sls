include:
  - /formulas/k8s-gitlab-runner/install
  - /formulas/common/helm/install

# Ensure Helm is installed and configured before proceeding
helm_installed:
  test.nop:
    - require:
      - sls: /formulas/common/helm/install

# Create namespace for GitLab Runner
gitlab_runner_namespace:
  k8s.namespace_present:
    - namespace: {{ pillar.get('gitlab_runner_namespace', 'gitlab-runner') }}
    - require:
      - test: helm_installed

# Add the GitLab Runner Helm repository
add_gitlab_runner_repo:
  cmd.run:
    - name: helm repo add gitlab-runner https://charts.gitlab.io
    - unless: helm repo list | grep -q "gitlab-runner"
    - require:
      - test: helm_installed

# Update Helm repositories to ensure the latest charts are available
update_helm_repos:
  cmd.run:
    - name: helm repo update
    - require:
      - cmd: add_gitlab_runner_repo

# Install or upgrade GitLab Runner using Helm with configurable settings
install_gitlab_runner:
  cmd.run:
    - name: helm upgrade --install gitlab-runner gitlab-runner/gitlab-runner --namespace {{ pillar['res-k8s-git-runner']['gitlab_runner_namespace'] }} --create-namespace --set gitlabUrl='{{ pillar['res-k8s-git-runner']['gitlab_url'] }}' --set runnerRegistrationToken='{{ pillar['res-k8s-git-runner']['runner_registration_token'] }}' --set runners.privileged={{ pillar['res-k8s-git-runner']['runner_privileged'] }} --set runners.tags={{ pillar['res-k8s-git-runner']['runner_tags']| join(',') }} --wait
    - require:
      - k8s: gitlab_runner_namespace
      - cmd: update_helm_repos
    - unless: kubectl get deployment -n {{ pillar['res-k8s-git-runner']['gitlab_runner_namespace'] }} | grep -q "gitlab-runner"