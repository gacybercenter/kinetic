# Cilium Pillar Example (Fixed)

The error you encountered (`nil pointer evaluating interface {}.name` in `hubble/tls-helm/server-secret.yaml`) occurs because the Cilium chart expects a `cluster.name` value when Hubble is enabled (for certificate generation), but it wasn't being passed correctly or the values structure was incomplete.

## Recommended Pillar

```yaml
res-k8s:
  cilium:
    values:
    cluster:
      name: "kubernetes"   # Must be set when hubble.enabled=true
    
    # Core CNI settings
    ipam:
      mode: kubernetes
    kubeProxyReplacement: true
    routingMode: tunnel
    tunnelProtocol: vxlan
    
    # Set MTU explicitly to 1500 (Cilium often defaults to 9000 which breaks many networks)
    mtu: 1500
    
    ipv4:
      enabled: true
    ipv6:
      enabled: false
    
    # Operator
    operator:
      unmanaged: false
    
    # Hubble (observability) - set tls.auto.method if you hit cert errors
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
      tls:
        auto:
          # Use helm method to generate certs (requires cluster.name)
          method: helm
          # Alternatively, disable TLS cert generation if having issues:
          # enabled: false
    
    # Performance & security
    bpf:
      masquerade: true
      preallocateMaps: true
    policy:
      enforcement: default
    prometheus:
      enabled: true
    
    # Additional common settings to avoid template errors
    cni:
      chainingMode: none
    
    # You can add/override any other values from the official chart here:
    # https://github.com/cilium/cilium/blob/master/install/kubernetes/cilium/values.yaml
```

## Usage

The `k8s_helm.helm_release_present` state (with `pillar_key: cilium:values`) will automatically fetch and merge these values.

**Important**: The `cluster.name` key is required when Hubble TLS auto-generation is enabled. The example above should resolve the nil pointer error.

After updating your pillar, re-apply the state:

```bash
salt '*' state.apply formulas.common.k8s-cilium
```
