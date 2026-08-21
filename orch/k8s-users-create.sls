{% set k8s = salt['pillar.get']('k8s') %}
# Define user details (these could be parameterized via pillar data if needed)
{% set username = salt['pillar.get']('user') %}
{% set access_type = salt['pillar.get']('access_type', 'namespace') %}  # Default to 'namespace'; can be 'cluster-admin'
{% set namespace = salt['pillar.get']('namespace', 'default') %}  # Default namespace if access_type is 'namespace'
{% set user_group = salt['pillar.get']('user_group', 'developers') %}  # Optional group for organization in Kubernetes

# Step 1: Validate access_type to ensure it's either 'cluster-admin' or 'namespace'
validate_access_type:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if [ "{{ access_type }}" != "cluster-admin" ] && [ "{{ access_type }}" != "namespace" ]; then
            echo "Error: Invalid access_type '{{ access_type }}'. Must be 'cluster-admin' or 'namespace'."
            exit 1
          fi
    - tgt: '{{ k8s }}'
    - output_loglevel: info

# Step 2: Check if username is already in use in the cluster
check_username_availability:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          if kubectl get csr {{ username }}-csr >/dev/null 2>&1; then
            echo "Error: Username '{{ username }}' is already in use (CSR exists). Please choose a different username."
            exit 1
          fi
          if [ "{{ access_type }}" = "cluster-admin" ] && kubectl get clusterrolebinding {{ username }}-cluster-admin-binding >/dev/null 2>&1; then
            echo "Error: Username '{{ username }}' is already in use (ClusterRoleBinding exists). Please choose a different username."
            exit 1
          fi
          if [ "{{ access_type }}" != "cluster-admin" ] && kubectl get rolebinding {{ username }}-rolebinding -n {{ namespace }} >/dev/null 2>&1; then
            echo "Error: Username '{{ username }}' is already in use (RoleBinding exists in namespace {{ namespace }}). Please choose a different username."
            exit 1
          fi
          echo "Username '{{ username }}' is available."
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: validate_access_type

# Step 3: Create a private key for the new user on the control plane node
create_user_private_key:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          openssl genrsa -out /tmp/{{ username }}.key 4096
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.key
    - require:
      - salt: check_username_availability

# Step 4: Create a Certificate Signing Request (CSR) for the user
create_user_csr:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          openssl req -new -key /tmp/{{ username }}.key -out /tmp/{{ username }}.csr -subj "/CN={{ username }}/O={{ user_group }}"
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.csr
    - require:
      - salt: create_user_private_key

# Step 5: Create a Kubernetes CSR object for the user
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
            request: $(cat /tmp/{{ username }}.csr | base64 | tr -d '\n')
            signerName: kubernetes.io/kube-apiserver-client
            expirationSeconds: 31556952  # 1 year; adjust as needed
            usages:
            - client auth
          EOF
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - unless: kubectl get csr {{ username }}-csr
    - require:
      - salt: create_user_csr 

# Step 6: Approve the CSR
approve_user_csr:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: kubectl certificate approve {{ username }}-csr
    - tgt: '{{ k8s }}'
    - unless: kubectl get csr {{ username }}-csr -o jsonpath='{.status.certificate}' | grep -q .
    - require:
      - salt: create_k8s_csr_object

# Step 7: Retrieve the signed certificate
retrieve_user_certificate:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: kubectl get csr {{ username }}-csr -o jsonpath='{.status.certificate}' | base64 -d > /tmp/{{ username }}.crt
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.crt
    - require:
      - salt: approve_user_csr

# Step 8: Create a kubeconfig file for the user
create_user_kubeconfig:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl config set-cluster kubernetes --server=https://$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}' | cut -d'/' -f3) --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs=true --kubeconfig=/tmp/{{ username }}.kubeconfig
          kubectl config set-credentials {{ username }} --client-certificate=/tmp/{{ username }}.crt --client-key=/tmp/{{ username }}.key --embed-certs=true --kubeconfig=/tmp/{{ username }}.kubeconfig
          kubectl config set-context {{ username }}@kubernetes --cluster=kubernetes --user={{ username }} --kubeconfig=/tmp/{{ username }}.kubeconfig
          kubectl config use-context {{ username }}@kubernetes --kubeconfig=/tmp/{{ username }}.kubeconfig
    - tgt: '{{ k8s }}'
    - cwd: /tmp
    - creates: /tmp/{{ username }}.kubeconfig
    - require:
      - salt: retrieve_user_certificate

# Step 9: Conditionally assign access based on access_type
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

# Step 10: Create a Kubernetes Secret with the base64-encoded kubeconfig in the default namespace
create_kubeconfig_secret:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          kubectl create secret generic {{ username }}-kubeconfig \
            --from-file=kubeconfig-base64=/tmp/{{ username }}.kubeconfig \
            --namespace=default \
            --dry-run=client -o yaml | kubectl apply -f -
          echo "{
            \"username\": \"{{ username }}\",
            \"access_type\": \"{{ access_type }}\",
            \"secret_name\": \"{{ username }}-kubeconfig\",
            \"namespace\": \"default\",
            \"instructions\": [
              \"Using Pepper CLI: Run 'pepper --client=local {{ k8s }} cmd.run \\\"kubectl get secret {{ username }}-kubeconfig -n default -o jsonpath=\\\\\\\"{.data.kubeconfig-base64}\\\\\\\" | base64 -d > ~/.kube/{{ username }}-config\\\"\"' to retrieve and decode the kubeconfig.\",
              \"Parse the Secret programmatically with Python: 'import json, base64; response = client.local(\"{{ k8s }}\", \"cmd.run\", \"kubectl get secret {{ username }}-kubeconfig -n default -o json\"); secret_data = json.loads(response[\"return\"][0][\"{{ k8s }}\"])[\"data\"][\"kubeconfig-base64\"]; decoded = base64.b64decode(secret_data).decode(\"utf-8\")'.\",
              \"Save the decoded kubeconfig to a file: 'with open(\"~/.kube/{{ username }}-config\", \"w\") as f: f.write(decoded)'.\",
              \"Use it with kubectl: 'kubectl --kubeconfig=~/.kube/{{ username }}-config get pods' or merge into default kubeconfig with 'export KUBECONFIG=~/.kube/{{ username }}-config:~/.kube/config'.\"
            ],
            \"status\": \"Kubeconfig stored as a Secret for {{ username }} in default namespace\"
          }"
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_user_kubeconfig
      {% if access_type == 'cluster-admin' %}
      - salt: create_cluster_admin_rolebinding
      {% else %}
      - salt: create_namespace_rolebinding
      {% endif %}

# Step 11: Clean up temporary files after creating the Secret
cleanup_temporary_files:
  salt.function:
    - name: cmd.run
    - kwarg:
        cmd: |
          for file in /tmp/{{ username }}.key /tmp/{{ username }}.csr /tmp/{{ username }}.crt /tmp/{{ username }}.kubeconfig; do
            if [ -f "$file" ]; then
              rm -f "$file"
              echo "Deleted temporary file: $file"
            else
              echo "Temporary file not found: $file"
            fi
          done
    - tgt: '{{ k8s }}'
    - output_loglevel: info
    - require:
      - salt: create_kubeconfig_secret