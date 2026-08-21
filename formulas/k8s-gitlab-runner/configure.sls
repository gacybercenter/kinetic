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

# Add the GitLab Runner Helm repository using the custom Helm module
add_gitlab_runner_repo:
  k8s_helm.helm_repo_present:
    - repo_name: gitlab-runner
    - repo_url: https://charts.gitlab.io
    - require:
      - test: helm_installed

# Install or upgrade GitLab Runner using the custom Helm module with configurable settings
install_gitlab_runner:
  k8s_helm.helm_release_present:
    - release_name: gitlab-runner
    - chart_name: gitlab-runner/gitlab-runner
    - namespace: {{ pillar['res-k8s-git-runner']['gitlab_runner_namespace'] }}
    - values_dict:
        gitlabUrl: {{ pillar['res-k8s-git-runner']['gitlab_url'] | json }}
        runnerRegistrationToken: {{ pillar['res-k8s-git-runner']['runner_registration_token'] | json }}
        runners:
          config: |
            [[runners]]
              [runners.kubernetes]
                privileged = {{ pillar['res-k8s-git-runner']['runner_privileged'] | lower }}
                allow_privileged_escalation = true
                [runners.kubernetes.pod_annotations]
                  "container.apparmor.security.beta.kubernetes.io/build" = "unconfined"
        rbac:
          create: true
    - wait_timeout: 300
    - wait_interval: 10
    - keep_values_file: True
    - require:
      - k8s: gitlab_runner_namespace
      - k8s_helm: add_gitlab_runner_repo