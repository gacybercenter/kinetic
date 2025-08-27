{% set k8s = salt['pillar.get']('k8s') %}

# Step 1: Create namespace for EFK if it doesn't exist
create_efk_namespace:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl get namespace {{ pillar.get('efk_namespace', 'efk') }} || kubectl create namespace {{ pillar.get('efk_namespace', 'efk') }}
    - tgt: '{{ k8s }}'
    - output_loglevel: info

# Step 2: Apply EFK configuration (Elasticsearch via Helm)
k8s_efk_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.k8s-efk.install
    - require:
      - salt: create_efk_namespace

# Step 3: Apply Fluent Bit configuration via Helm
k8s_fluent_bit_install:
  salt.state:
    - tgt: '{{ k8s }}'
    - sls: formulas.common.fluent-bit.install