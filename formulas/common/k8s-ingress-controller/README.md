# k8s-ingress-controller Formula

Deploys Traefik as a dual (internal + external) ingress controller using Gateway API and MetalLB.

## Purpose

This formula sets up a complete ingress solution with:
- MetalLB for LoadBalancer IP management
- Two Traefik instances (internal on 10.150.1.43, external on 10.150.1.247)
- Gateway API `Gateway` resources
- Protected Traefik dashboard with basic auth
- Automatic TLS certificate management

## Pillar Requirements

The formula expects data under `res-k8s:lbs:ingress`. See the attached pillar example for the full structure.

Key sections:
- `ips.external` and `ips.internal`
- `ingress.providers.kubernetesGateway.enabled: true`
- `ingress.gatewayClass.enabled: true`
- Custom `ports` for external exposure (9080, 9443)
- `extraObjects` for dashboard auth secret and middleware
- `ingressRoute.dashboard` for the protected dashboard

## Usage

```yaml
include:
  - /formulas/common/k8s-ingress-controller
```

## What it installs

1. **MetalLB** with two IP pools (`lb-pool-internal`, `lb-pool-external`)
2. **Traefik** Helm releases (`traefik-internal`, `traefik-external`)
3. Two `Gateway` resources (`traefik-internal`, `traefik-external`)
4. TLS certificates (`int-ingress-tls-secret`, `ext-ingress-tls-secret`)
5. Dashboard authentication middleware

## Dependencies

- `formulas/common/helm`
- `formulas/common/k8s` (namespace, metallb, gateway_present, certmanager states)
- cert-manager with `ClusterIssuer: cyberrange-ca-issuer`
- Existing `GatewayClass` named `traefik`

## Notes

- Uses **Gateway API** instead of traditional Ingress
- Two separate Traefik releases to support different external IPs
- Dashboard available at `https://dashboard.services.gacyberrange.org`
- Update the default password in the pillar before production use

Last updated: July 2025
