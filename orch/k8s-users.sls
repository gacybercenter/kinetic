{% set k8s = salt['pillar.get']('k8s') %}
# Define user details (these could be parameterized via pillar data if needed)
{% set username = salt['pillar.get']('user') %}
{% set access_type = salt['pillar.get']('access_type', 'namespace') %}  # Default to 'namespace'; can be 'cluster-admin'
{% set namespace = salt['pillar.get']('namespace', 'default') %}  # Default namespace if access_type is 'namespace'
{% set user_group = salt['pillar.get']('user_group', 'developers') %}  # Optional group for organization in Kubernetes

# Step 2: Create a private key for the new user on the control plane node
create_user_private_key:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          openssl genrsa -out {{ username }}.key 4096
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.key
    - require:
      - salt: ensure_kubectl_installed

# Step 3: Create a Certificate Signing Request (CSR) for the user
create_user_csr:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          openssl req -new -key {{ username }}.key -out {{ username }}.csr -subj "/CN={{ username }}/O={{ user_group }}"
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.csr
    - require:
      - salt: create_user_private_key

# Step 4: Create a Kubernetes CSR object for the user
create_k8s_csr_object:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          cat <<EOF | kubectl apply -f -
          apiVersion: certificates.k8s.io/v1
          kind: CertificateSigningRequest
          metadata:
            name: {{ username }}-csr
          spec:
            request: $(cat {{ username }}.csr | base64 | tr -d '\n')
            signerName: kubernetes.io/kube-apiserver-client
            expirationSeconds: 86400  # 1 day; adjust as needed
            usages:
            - client auth
          EOF
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - unless: kubectl get csr {{ username }}-csr
    - require:
      - salt: create_user_csr 

# Step 5: Approve the CSR
approve_user_csr:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: kubectl certificate approve {{ username }}-csr
    - tgt: '{{ k8s }}'
    - unless: kubectl get csr {{ username }}-csr -o jsonpath='{.status.certificate}' | grep -q .
    - require:
      - salt: create_k8s_csr_object

# Step 6: Retrieve the signed certificate
retrieve_user_certificate:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: kubectl get csr {{ username }}-csr -o jsonpath='{.status.certificate}' | base64 -d > {{ username }}.crt
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.crt
    - require:
      - salt: approve_user_csr

# Step 7: Create a kubeconfig file for the user
create_user_kubeconfig:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl config set-cluster kubernetes --server=https://$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' | cut -d'/' -f3) --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true --kubeconfig={{ username }}.kubeconfig
          kubectl config set-credentials {{ username }} --client-certificate=/tmp/{{ username }}.crt --client-key=/tmp/{{ username }}.key --embed-certs=true --kubeconfig={{ username }}.kubeconfig
          kubectl config set-context {{ username }}@kubernetes --cluster=kubernetes --user={{ username }} --kubeconfig={{ username }}.kubeconfig
          kubectl config use-context {{ username }}@kubernetes --kubeconfig={{ username }}.kubeconfig
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.kubeconfig
    - require:
      - salt: retrieve_user_certificate

# Step 8: Conditionally assign access based on access_type
{% if access_type == 'cluster-admin' %}
# Assign cluster-admin access using the built-in cluster-admin ClusterRole
create_cluster_admin_rolebinding:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          cat <<EOF | kubectl apply -f -
          apiVersion: rbac.authorization.k8s.io/v1
          kind: ClusterRoleBinding
          metadata:
            name: {{ username }}-cluster-admin-binding
          subjects:
          - kind: User
            name: {{ username }}
            apiGroup: rbac.authorization.k8s.io
          roleRef:
            kind: ClusterRole
            name: cluster-admin
            apiGroup: rbac.authorization.k8s.io
          EOF
    - tgt: '{{ k8s }}'
    - unless: kubectl get clusterrolebinding {{ username }}-cluster-admin-binding
    - require:
      - salt: create_user_kubeconfig
{% else %}
# Create a namespace-scoped Role for limited access
create_namespace_role:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          cat <<EOF | kubectl apply -f -
          apiVersion: rbac.authorization.k8s.io/v1
          kind: Role
          metadata:
            namespace: {{ namespace }}
            name: {{ username }}-role
          rules:
          - apiGroups: [""]
            resources: ["pods", "services"]
            verbs: ["get", "list", "watch"]
          - apiGroups: ["apps"]
            resources: ["deployments"]
            verbs: ["get", "list", "watch"]
          EOF
    - tgt: '{{ k8s }}'
    - unless: kubectl get role {{ username }}-role -n {{ namespace }}
    - require:
      - salt: create_user_kubeconfig

# Bind the namespace-scoped Role to the user
create_namespace_rolebinding:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          cat <<EOF | kubectl apply -f -
          apiVersion: rbac.authorization.k8s.io/v1
          kind: RoleBinding
          metadata:
            namespace: {{ namespace }}
            name: {{ username }}-rolebinding
          subjects:
          - kind: User
            name: {{ username }}
            apiGroup: rbac.authorization.k8s.io
          roleRef:
            kind: Role
            name: {{ username }}-role
            apiGroup: rbac.authorization.k8s.io
          EOF
    - tgt: '{{ k8s }}'
    - unless: kubectl get rolebinding {{ username }}-rolebinding -n {{ namespace }}
    - require:
      - salt: create_namespace_role
{% endif %}

# Step 9: Optionally, move kubeconfig to a secure location or distribute it (example: log location)
log_kubeconfig_location:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          echo "Kubeconfig for {{ username }} created at /tmp/{{ username }}.kubeconfig. Please secure and distribute it to the user. Access type: {{ access_type }}\n"
          echo "kubeconfig:\n"
          cat /tmp/{{ username }}.kubeconfig
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_user_kubeconfig