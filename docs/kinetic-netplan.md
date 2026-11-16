# kinetic-netplan Module

SaltStack execution and state modules for generating and applying Netplan network configurations on bare-metal hosts. The module supports bonding, bridging, host-type differentiation, and persistent promiscuous mode.

## Features

- Generate Netplan v2 configurations from pillar data
- Automatic bonding (802.3ad) when multiple interfaces are defined for a network
- Bridge creation for all non-management networks
- Different handling for controller vs. non-controller hosts on the management network
- One-shot systemd service for persistent promiscuous mode on non-management interfaces
- Optional immediate application via `netplan apply`

## Execution Module Functions

### generate_config

Generates a complete Netplan configuration dictionary based on pillar data under `hosts:<host_type>:networks`.

Key behaviors:
- Uses LACP bonds (`mode: 802.3ad`, `lacp-rate: fast`) when a network has multiple physical interfaces
- Creates a bridge for every non-management network
- Management network:
  - Controllers: bridged via `management_br`
  - Non-controllers: uses the physical/bond interface directly
- All interfaces get `mtu: 9000` and `dhcp4: false`
- Default route and nameservers come from the top-level `dhcp-options` pillar
- Management IP is taken from `bmh:<minion_id>:network:management_ip`

### apply_config

Writes the generated configuration to `/etc/netplan/01-netcfg.yaml` (mode 0600, owned by root) and runs `netplan apply`. Returns success/failure and any changes.

### promisc_mode

Creates and enables a one-shot systemd service (`promisc-mode.service`) that persistently brings the physical interfaces of the specified (or auto-detected non-management) networks into promiscuous mode. This is typically required for Ceph public/cluster networks or other L2 use cases.

If `networks` is not provided, the function automatically selects all non-management networks defined for the host's type in pillar.

## State Module Functions

### config_present

Wrapper around `generate_config` (and optionally `apply_config`).

Parameters:
- `pillar_key` – Pillar root containing host networking data (default: `res-k8s`)
- `apply_immediately` – Whether to run `netplan apply` after generating the config

### promisc_mode_enabled

Wrapper around the `promisc_mode` execution function. Accepts an optional `networks` list; if omitted, it uses all non-management networks from pillar.

## Example Usage

```yaml
ensure_netplan_config:
  kinetic_netplan.config_present:
    - pillar_key: res-k8s
    - apply_immediately: true

ensure_promiscuous_mode:
  kinetic_netplan.promisc_mode_enabled:
    - networks:
        - sfe
        - sbe
        - priv
```

## Notes

- The module assumes a Netplan v2 renderer of `networkd`.
- Bond parameters are hardcoded to `mode: 802.3ad` with fast LACP; adjust the execution module if different bonding modes are required.
- Promiscuous mode is implemented via a separate one-shot service rather than Netplan itself, because Netplan does not expose a native `promisc` option in all versions.
- The generated configuration never enables DHCP; all addressing information is expected to come from pillar (`bmh` + `networking` + `dhcp-options`).

Last updated: September 2026
```