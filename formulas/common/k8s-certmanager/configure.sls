include: /formulas/common/k8s-certmanager/install

ensure_selfsigned_issuer:
  k8s.certmanager_issuer_present:
    - namespace: cert-manager
    - issuer_name: selfsigned-issuer
    - issuer_kind: CusterIssuer
    - spec:
        selfSigned: {}


# Ensure a Let's Encrypt Issuer is present
ensure_letsencrypt_issuer:
  k8s.certmanager_issuer_present:
    - namespace: cert-manager
    - issuer_name: letsencrypt-prod
    - issuer_kind: ClusterIssuer # Use 'ClusterIssuer' if you want a cluster-wide issuer
    - spec:
        acme:
          # Use Let's Encrypt production server
          server: https://acme-v02.api.letsencrypt.org/directory
          # Email address for ACME account (replace with your email)
          email: user@example.com
          # Secret to store the ACME account private key
          privateKeySecretRef:
            name: letsencrypt-prod-key
          # Solvers for domain validation (HTTP01 in this example)
          solvers:
            - http01:
                ingress:
                  class: nginx  # Adjust based on your ingress controller