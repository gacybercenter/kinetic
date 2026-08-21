exec_start="kubectl -n rook-ceph exec -ti vault-1 -- env VAULT_ADDR=https://vault:8200"
source /tmp/.vault-token

ROOK_NAMESPACE=rook-ceph
ROOK_VAULT_SA=rook-vault-auth
ROOK_SYSTEM_SA=rook-ceph-system
ROOK_OSD_SA=rook-ceph-osd
CSI_PROVISIONER_SA="rook-ceph-rbd-csi-ceph-com-ctrlplugin-sa"
CSI_NODE_SA="rook-ceph-rbd-csi-ceph-com-nodeplugin-sa"

VAULT_POLICY_NAME="rook"
VAULT_ROLE_NAME="rook-ceph"
VAULT_CSI_ROLE_NAME="rook-ceph-csi"

# ======================
# 1. Create ServiceAccount for Vault
# ======================
kubectl -n "$ROOK_NAMESPACE" create serviceaccount "$ROOK_VAULT_SA"

# ======================
# 2. Create ClusterRoleBinding (TokenReview permissions)
# ======================
kubectl create clusterrolebinding vault-tokenreview-binding \
  --clusterrole=system:auth-delegator \
  --serviceaccount="$ROOK_NAMESPACE:$ROOK_VAULT_SA"

# ======================
# 3. Manually create the long-lived ServiceAccount token Secret
#    (required on Kubernetes 1.24+)
# ======================
kubectl -n "$ROOK_NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ROOK_VAULT_SA}-token
  annotations:
    kubernetes.io/service-account.name: ${ROOK_VAULT_SA}
type: kubernetes.io/service-account-token
EOF

# ======================
# 4. Extract the token and CA
# ======================
VAULT_SA_SECRET_NAME="${ROOK_VAULT_SA}-token"

SA_JWT_TOKEN=$(kubectl -n "$ROOK_NAMESPACE" get secret "$VAULT_SA_SECRET_NAME" \
  -o jsonpath="{.data.token}" | base64 --decode)

SA_CA_CRT=$(kubectl -n "$ROOK_NAMESPACE" get secret "$VAULT_SA_SECRET_NAME" \
  -o jsonpath="{.data['ca\.crt']}" | base64 --decode)

# ======================
# 5. Get Kubernetes API server address
# ======================
K8S_HOST=$(kubectl config view --minify --flatten -o jsonpath="{.clusters[0].cluster.server}")

# ======================
# 6. Enable Kubernetes auth method in Vault
# ======================
$exec_start vault login $VAULT_TOKEN
$exec_start vault auth enable kubernetes || echo "kubernetes not  enabled"

# ======================
# 7. Configure the Kubernetes auth method
# ======================
# Start a temporary proxy to get the issuer
kubectl proxy &
proxy_pid=$!
sleep 2

$exec_start vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_JWT_TOKEN" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$SA_CA_CRT" \
  issuer="$(curl --silent http://127.0.0.1:8001/.well-known/openid-configuration | jq -r .issuer)"

kill $proxy_pid
$exec_start vault secrets enable -path=rook kv-v2
$exec_start vault policy delete "$VAULT_POLICY_NAME"
$exec_start vault policy write "$VAULT_POLICY_NAME" - <<EOF
path "rook/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "rook/metadata/*" {
  capabilities = ["list", "read", "delete", "update"]
}
path "rook/data/ceph-csi/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "rook/metadata/ceph-csi/*" {
  capabilities = ["list", "read", "delete", "update"]
}
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/internal/ui/mounts/*" {
  capabilities = ["read"]
}
EOF

# ======================
# 8. Create the Vault role for Rook
# ======================
$exec_start vault write auth/kubernetes/role/"$ROOK_NAMESPACE" \
  bound_service_account_names="$ROOK_SYSTEM_SA,$ROOK_OSD_SA" \
  bound_service_account_namespaces="$ROOK_NAMESPACE" \
  policies="$VAULT_POLICY_NAME" \
  ttl=1440h \
  audience="https://kubernetes.default.svc.cluster.local"

# ======================
# 9. Role for CSI pods (PVC encryption)
# ======================
$exec_start vault write auth/kubernetes/role/"$VAULT_CSI_ROLE_NAME" \
  bound_service_account_names="$CSI_PROVISIONER_SA,$CSI_NODE_SA" \
  bound_service_account_namespaces="$ROOK_NAMESPACE" \
  policies="$VAULT_POLICY_NAME" \
  ttl=1440h \
  audience="https://kubernetes.default.svc.cluster.local"
# 9.  break glass approle #

$exec_start vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

$exec_start vault auth enable approle

$exec_start vault write auth/approle/role/admin \
  token_policies="admin" \
  token_ttl=1h \
  token_max_ttl=4h

export role_id=$($exec_start vault read auth/approle/role/admin/role-id)
export secret_id=$($exec_start vault write -f auth/approle/role/admin/secret-id)

echo "roleid = $role_id"
echo "secret_id = $secret_id"
