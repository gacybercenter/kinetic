include:
  - /formulas/runai/install

{# Same NGC login as the helm repo: username $oauthtoken, password from
   res-k8s:gpu:runai:ngc_api_key. The secret is the dockerconfigjson
   kubelet uses to pull from nvcr.io. Equivalent to:
     kubectl create secret docker-registry runai-reg-creds -n runai \
       --docker-server=nvcr.io \
       --docker-username='$oauthtoken' \
       --docker-password=<NGC_API_KEY> \
       --docker-email='$oauthtoken'
   Override namespace / secret name / registry under res-k8s:gpu:runai. #}
{% set runai = pillar.get('res-k8s', {}).get('gpu', {}).get('runai', {}) %}
{% set runai_ns = runai.get('namespace', 'runai') %}
{% set pull_secret = runai.get('pull_secret', 'runai-reg-creds') %}
{% set registry = runai.get('registry', 'nvcr.io') %}
{% set ngc_user = '$oauthtoken' %}
{% set ngc_key = (runai.get('ngc_api_key') or '') | trim %}
{% set admin = runai.get('admin_account') or {} %}
{% set admin_name = (admin.get('name') or '') | trim %}
{% set admin_pass = admin.get('pass') or '' %}
{% set admin_secret = admin.get('secret_name', 'runai-admin') %}
{# Control plane is a separate release from the cluster chart, installed
   in the same runai namespace. Values are the chart's own values.yaml
   shape, including tenantsManager.config.adminUsername/adminPassword. #}
{% set cp_ns = runai.get('controlplane_namespace', runai_ns) %}
{% set cp_chart = runai.get('controlplane_chart', 'runai/control-plane') %}
{% set cp_release = runai.get('controlplane_release', 'runai-backend') %}
{% set cp_version = runai.get('controlplane_version') %}
{% set cp_values = (runai.get('values') or {}).get('controlplane') %}

ensure_runai_repo:
  k8s_helm.helm_repo_present:
    - repo_name: runai
    - repo_url: https://helm.ngc.nvidia.com/nvidia/runai
    - username: "$oauthtoken"
    - password_pillar: res-k8s:gpu:runai:ngc_api_key

ensure_runai_namespace:
  k8s.namespace_present:
    - namespace: {{ runai_ns }}

{% if not ngc_key %}
ensure_runai_pull_secret:
  test.fail_without_changes:
    - name: {{ pull_secret }}
    - comment: "res-k8s:gpu:runai:ngc_api_key is missing or empty. The nvcr.io pull secret needs the same NGC API key as the helm repo."
{% else %}
{# containerd looks up nvcr.io; some NGC examples key the secret as
   https://nvcr.io. Store both unless registry is overridden. #}
{% set registries = [registry] %}
{% if registry == 'nvcr.io' %}
{% do registries.append('https://nvcr.io') %}
{% endif %}
{% set auths = {} %}
{% for server in registries %}
{% do auths.update({server: {
  'username': ngc_user,
  'password': ngc_key,
  'email': ngc_user,
  'auth': (ngc_user ~ ':' ~ ngc_key) | base64_encode,
}}) %}
{% endfor %}
{% set dockerconfig = {'auths': auths} %}
ensure_runai_pull_secret:
  k8s.secret_present:
    - secret_name: {{ pull_secret }}
    - namespace: {{ runai_ns }}
    - secret_type: kubernetes.io/dockerconfigjson
    - data:
        .dockerconfigjson: {{ dockerconfig | tojson | yaml_dquote }}
    - require:
      - k8s: ensure_runai_namespace
{% endif %}

{# Control-plane login. Pillar is GPG-encrypted; the renderer decrypts it
   before this state renders. Keys match the keycloak-admin secret. #}
{% if not admin_name or not (admin_pass | trim) %}
ensure_runai_admin_secret:
  test.fail_without_changes:
    - name: {{ admin_secret }}
    - comment: "res-k8s:gpu:runai:admin_account needs name and pass."
{% else %}
ensure_runai_admin_secret:
  k8s.secret_present:
    - secret_name: {{ admin_secret }}
    - namespace: {{ runai_ns }}
    - secret_type: Opaque
    - data:
        username: {{ admin_name | yaml_dquote }}
        password: {{ admin_pass | yaml_dquote }}
    - require:
      - k8s: ensure_runai_namespace
{% endif %}
{% if not cp_values %}
install_runai_backend:
  test.fail_without_changes:
    - name: {{ cp_release }}
    - comment: "res-k8s:gpu:runai:values:controlplane is missing. That dict is passed to helm as the control-plane chart values."
{% else %}
install_runai_backend:
  k8s_helm.helm_release_present:
    - release_name: {{ cp_release }}
    - chart_name: {{ cp_chart | yaml_dquote }}
    - namespace: {{ cp_ns }}
    - pillar_key: res-k8s:gpu:runai:values:controlplane
{%- if cp_version %}
    - version: {{ cp_version | yaml_dquote }}
{%- endif %}
    - wait: false
    - wait_timeout: 900
    - wait_interval: 15
    - require:
      - k8s_helm: ensure_runai_repo
      - k8s: ensure_runai_namespace
      - k8s: ensure_runai_pull_secret
{% endif %}
