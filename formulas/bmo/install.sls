include:
  - /formulas/common/k8s-certmanager/install

# Validate deployment options
validate_deployment_bmo_ironic:
  test.fail_without_changes:
    - name: "Nothing to deploy: deploy_bmo and deploy_ironic are both false"
    - failhard: True
    - unless: {{ pillar['deploy_bmo'] }} or {{ pillar['deploy_ironic'] }}
valid_deployment_mariadb_tls:
  test.fail_without_changes:
    - name: "MariaDB deployment requires TLS"
    - failhard: True
    - onlyif: {{ pillar['deploy_mariadb'] }} and  ! {{ pillar['deploy_tls'] }}

# Install dependencies (kustomize, kubectl)
install_dependencies:
  pkg.installed:
    - pkgs:
        - kubectl
        - curl
        - apache2-utils
  cmd.run:
    - name: |
        curl -sL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.1/kustomize_v5.4.1_linux_amd64.tar.gz | tar xz -C /usr/local/bin/ && chmod +x /usr/local/bin/kustomize
    - unless: test -x /usr/local/bin/kustomize && kustomize version | grep v5.4.1
    - require:
      - pkg: install_dependencies

clone_bmo_repo:
  git.latest:
    - name: https://github.com/metal3-io/baremetal-operator.git
    - target: {{ pillar['script_dir'] }}
    - force_clone: true
    - require:
      - pkg: install_dependencies

# Create directories for Ironic data and auth
ironic_directories:
  file.directory:
    - names:
        - {{ pillar['ironic_data_dir'] }}
        - {{ pillar['ironic_auth_dir'] }}
    - mode: 755
    - makedirs: True
    - require:
      - pkg: install_dependencies

# Create temporary overlay directories
temp_overlay_dirs:
  file.directory:
    - names:
        - {{ pillar['temp_bmo_overlay'] }}
        - {{ pillar['temp_ironic_overlay'] }}
    - mode: 755
    - makedirs: True
    - clean: True
    - require:
      - file: ironic_directories

#ironic_cacert_secret:
#  cmd.run:
#    - name: kubectl create secret generic ironic-cacert --from-literal=cacert='' --namespace={{ pillar['bmo_namespace'] }}
#    - onlyif: ! {{ pillar['deploy_tls'] }}
#    - unless: kubectl get secret ironic-cacert --namespace {{ pillar['bmo_namespace'] }}
#    - require:
#      - cmd: bmo_ironic_namespace
#webhook_cert_secret:
#  cmd.run:
#    - name: kubectl create secret generic bmo-webhook-server-cert --from-literal=cert='' --namespace={{ pillar['bmo_namespace'] }}
#    - onlyif: ! {{ pillar['deploy_tls'] }}
#    - unless: kubectl get secret bmo-webhook-server-cert --namespace {{ pillar['bmo_namespace'] }}
#    - require:
#      - cmd: bmo_ironic_namespace

# Generate Ironic credentials if basic auth is enabled
{% if pillar['deploy_basic_auth'] %}
ironic_credentials_username:
  file.managed:
    - name: {{ pillar['ironic_auth_dir'] }}/ironic-username
    - contents: {{ pillar.get('ironic_username', grains['id'] | uuid) }}
    - mode: 600
    - unless: test -f {{ pillar['ironic_auth_dir'] }}/ironic-username
    - require:
      - file: ironic_directories
ironic_credentials_password:
  file.managed:
    - name: {{ pillar['ironic_auth_dir'] }}/ironic-password
    - contents: {{ pillar.get('ironic_password', grains['id'] | uuid) }}
    - mode: 600
    - unless: test -f {{ pillar['ironic_auth_dir'] }}/ironic-password
    - require:
      - file: ironic_directories

# Copy credentials to BMO overlay
bmo_credentials_username:
  file.managed:
    - name: {{ pillar['temp_bmo_overlay'] }}/ironic-username
    - source: {{ pillar['ironic_auth_dir'] }}/ironic-username
    - mode: 600
    - require:
      - file: ironic_credentials_username
      - file: ironic_credentials_password
      - file: temp_overlay_dirs
bmo_credentials_password:
  file.managed:
    - name: {{ pillar['temp_bmo_overlay'] }}/ironic-password
    - source: {{ pillar['ironic_auth_dir'] }}/ironic-password
    - mode: 600
    - require:
      - file: ironic_credentials_username
      - file: ironic_credentials_password
      - file: temp_overlay_dirs

# Generate htpasswd for Ironic
ironic_htpasswd:
  cmd.run:
    - name: htpasswd -n -b -B {{ pillar['ironic_username'] }} {{ pillar['ironic_password'] }} > {{ pillar['temp_ironic_overlay'] }}/ironic-htpasswd
    - unless: test -f {{ pillar['temp_ironic_overlay'] }}/ironic-htpasswd
    - require:
      - file: ironic_credentials_username
      - file: ironic_credentials_password
      - file: temp_overlay_dirs
{% endif %}

# Create namespace
bmo_ironic_namespace:
  cmd.run:
    - name: kubectl create namespace {{ pillar['bmo_namespace'] }} --dry-run=client -o yaml | kubectl apply -f -
    - unless: kubectl get namespace {{ pillar['bmo_namespace'] }}
    - require:
      - pkg: install_dependencies

# BMO kustomize overlay
{% if pillar['deploy_bmo'] %}
bmo_kustomize_overlay:
  file.managed:
    - name: {{ pillar['temp_bmo_overlay'] }}/kustomization.yaml
    - contents: |
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
          - ../../base
          - ../..//namespace
        namespace: {{ pillar['bmo_namespace'] }}
        {% if pillar['deploy_basic_auth'] %}
        components:
          - ../../components/basic-auth
        secretGenerator:
          - name: ironic-credentials
            namespace: {{ pillar['bmo_namespace'] }}
            literals:
              - username={{ pillar['ironic_username'] }}
              - password={{ pillar['ironic_password'] }}
        {% endif %}
        {% if pillar['deploy_tls'] %}
        components:
          - ../../components/tls
        {% endif %}
        configMapGenerator:
          - name: ironic
            behavior: create
            envs:
              - ironic.env
    - mode: 644
    - require:
      - file: temp_overlay_dirs
      {% if pillar['deploy_basic_auth'] %}
      - file: bmo_credentials_username
      - file: bmo_credentials_password
      {% endif %}

bmo_ironic_env:
  file.managed:
    - name: {{ pillar['temp_bmo_overlay'] }}/ironic.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - template: jinja
    - mode: 644
    - require:
      - file: temp_overlay_dirs

bmo_deploy:
  cmd.run:
    - name: kustomize build {{ pillar['temp_bmo_overlay'] }} | kubectl apply -f -
    - cwd: {{ pillar['temp_bmo_overlay'] }}
    - unless: kubectl get deployment -n {{ pillar['bmo_namespace'] }} baremetal-operator-controller-manager
    - require:
      - file: bmo_kustomize_overlay
      - file: bmo_ironic_env
      - cmd: bmo_ironic_namespace
{% endif %}

# Ironic kustomize overlay
{% if pillar['deploy_ironic'] %}
ironic_kustomize_overlay:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/kustomization.yaml
    - contents: |
        apiVersion: kustomize.config.k8s.io/v1beta1
        kind: Kustomization
        resources:
          - ../../namespace
        namespace: {{ pillar['bmo_namespace'] }}
        namePrefix: baremetal-operator-
        {% if pillar['deploy_basic_auth'] %}
        secretGenerator:
          - name: ironic-htpasswd
            namespace: {{ pillar['bmo_namespace'] }}
            files:
              - htpasswd=ironic-htpasswd
        {% if pillar['deploy_tls'] %}
        resources:
          - ../basic-auth_tls
        {% else %}
        resources:
          - ../../base
        components:
          - ../../components/basic-auth
        {% endif %}
        {% else %}
        {% if pillar['deploy_tls'] %}
        components:
          - ../../components/tls
        {% endif %}
        {% endif %}
        {% if pillar['deploy_mariadb'] %}
        components:
          - ../../components/mariadb
        {% endif %}
        configMapGenerator:
          - name: ironic-bmo-configmap
            behavior: create
            envs:
              - ironic_bmo_configmap.env
    - mode: 644
    - require:
      - file: temp_overlay_dirs
      {% if pillar['deploy_basic_auth'] %}
      - cmd: ironic_htpasswd
      {% endif %}

ironic_bmo_configmap:
  file.managed:
    - name: {{ pillar['temp_ironic_overlay'] }}/ironic_bmo_configmap.env
    - source: salt://formulas/bmo/files/ironic.env.j2
    - mode: 644
    - template: jinja
    - require:
      - file: temp_overlay_dirs
bmo_service:
  kubernetes.service_present:
    - name: bmo-ironic
    - 
    

# Update certificate.yaml for TLS and MariaDB
{% if pillar['deploy_tls'] %}
update_tls_certificate:
  file.replace:
    - name: {{ pillar['script_dir'] }}/ironic-deployment/components/tls/certificate.yaml
    - pattern: IRONIC_HOST_IP
    - repl: {{ pillar['ironic_endpoint_ip'] }}
    - require:
      - file: temp_overlay_dirs
{% endif %}
{% if pillar['deploy_mariadb'] %}
update_mariadb_certificate:
  file.replace:
    - name: {{ pillar['script_dir'] }}/ironic-deployment/components/mariadb/certificate.yaml
    - pattern: MARIADB_HOST_IP
    - repl: {{ pillar['mariadb_host_ip'] }}
    - require:
      - file: temp_overlay_dirs
{% endif %}

ironic_deploy:
  cmd.run:
    - name: kustomize build {{ pillar['temp_ironic_overlay'] }} | kubectl apply -f -
    - cwd: {{ pillar['temp_ironic_overlay'] }}
    - unless: kubectl get deployment -n {{ pillar['bmo_namespace'] }} baremetal-operator-ironic
    - require:
      - file: ironic_kustomize_overlay
      - file: ironic_bmo_configmap
      {% if pillar['deploy_tls'] %}
      - file: update_tls_certificate
      {% endif %}
      {% if pillar['deploy_mariadb'] %}
      - file: update_mariadb_certificate
      {% endif %}
{% endif %}

# Cleanup temporary files
{% if pillar['deploy_basic_auth'] %}
cleanup_bmo_credentials:
  file.absent:
    - names:
        - {{ pillar['temp_bmo_overlay'] }}/ironic-username
        - {{ pillar['temp_bmo_overlay'] }}/ironic-password
    - require:
      {% if pillar['deploy_bmo'] %}
      - cmd: bmo_deploy
      {% endif %}
    - onlyif: test -f {{ pillar['temp_bmo_overlay'] }}/ironic-username

cleanup_ironic_credentials:
  file.absent:
    - names:
        - {{ pillar['temp_ironic_overlay'] }}/ironic-htpasswd
    - require:
      {% if pillar['deploy_ironic'] %}
      - cmd: ironic_deploy
      {% endif %}
    - onlyif: test -f {{ pillar['temp_ironic_overlay'] }}/ironic-htpasswd
{% endif %}