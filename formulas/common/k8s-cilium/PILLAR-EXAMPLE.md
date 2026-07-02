# Cilium Pillar Example

Add the following to your pillar (e.g. in `pillar/k8s.sls` or a dedicated cilium pillar file):

```yaml
cilium:
  values:
    cluster:
      name: "my-cluster"
    
    ipam:
      mode: kubernetes
    
    kubeProxyReplacement: true
    
    operator:
      unmanaged: false
    
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
    
    routingMode: "tunnel"
    tunnelProtocol: "vxlan"
    
    ipv4:
      enabled: true
    ipv6:
      enabled: false
    
    policy:
      enforcement: default
    
    bpf:
      masquerade: true
      preallocateMaps: true
    
    prometheus:
      enabled: true

    # You can add any other Cilium Helm values here.
    # See: https://github.com/cilium/cilium/blob/master/install/kubernetes/cilium/values.yaml
```

## Usage

The `k8s_helm.helm_release_present` state will automatically fetch values from `pillar['cilium']['values']` using the `pillar_key: cilium:values` parameter.

You can override specific values per environment by using pillar merging or environment-specific pillars.
