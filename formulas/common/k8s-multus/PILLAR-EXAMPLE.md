# Multus Pillar Example

Add the following to your pillar (e.g. in `pillar/k8s.sls` or a dedicated multus pillar file):

```yaml
multus:
  values:
    # Basic Multus configuration
    image:
      repository: ghcr.io/k8snetworkplumbingwg/multus-cni
      tag: "v4.1.0"
      pullPolicy: IfNotPresent
    
    # Where to place the multus binary and config
    cni:
      binDir: /opt/cni/bin
      confDir: /etc/cni/net.d
      configFile: 00-multus.conf
    
    # Additional settings
    fullnameOverride: "multus"
    nameOverride: "multus"
    
    # Whether to install the Multus CNI plugin as a DaemonSet
    daemonset:
      enabled: true
    
    # Additional CNI plugins to install (optional)
    # You can add other plugins like whereabouts, macvlan, etc.
    # For a full list of available values, see the chart's values.yaml:
    # https://github.com/k8snetworkplumbingwg/helm-charts/blob/main/charts/multus-cni/values.yaml
```

## Usage

The `k8s_helm.helm_release_present` state will automatically fetch values from `pillar['multus']['values']` using the `pillar_key: multus:values` parameter.

Multus is typically used in combination with other CNIs (like Cilium) to provide multiple network interfaces to pods.
