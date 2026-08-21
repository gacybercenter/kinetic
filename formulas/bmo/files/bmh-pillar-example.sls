bmh:
  compute-133-26:
    online: true
    bmc:
      address: ipmi://10.100.0.85
      credentialsName: bmc-auth
    bootMACAddress: ac:1f:6b:7d:14:e9
    bootMode: UEFI
    image:
      checksum: http://10.150.1.41:6180/images/noble.checksum
      format: qcow2
      url: http://10.150.1.41:6180/images/noble.img
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    network:
      net-env: onprem
      management_ip: 10.150.1.75
    uuid: 00000000-0000-0000-0000-0cc47afbf280
  controller-133-32:
    online: true
    bmc:
      address: ipmi://10.100.0.87
      credentialsName: bmc-auth
    bootMACAddress: 00:25:90:5f:5f:a6
    bootMode: UEFI
    image:
      checksum: http://10.150.1.41:6180/images/noble.checksum
      format: qcow2
      url: http://10.150.1.41:6180/images/noble.img
    rootDeviceHints:
      deviceName: /dev/nvme0n1
    network:
      net-env: onprem
      management_ip: 10.150.1.76
    uuid: 00000000-0000-0000-0000-0CC47AFBF3AC
hosts:
  compute:
    style: physical
    role: compute
    enabled: True
    os: ubuntu2204-amd64
    uuids:
      - 00000000-0000-0000-0000-0CC47AFBF3B4
      - 00000000-0000-0000-0000-0CC47AFBF274
      - 00000000-0000-0000-0000-0CC47AFBF39C
      # - 00000000-0000-0000-0000-0CC47AFBF1A8
      # - 00000000-0000-0000-0000-0CC47AFBF2FC
      # - 00000000-0000-0000-0000-0CC47AFBF284
      # - 00000000-0000-0000-0000-0CC47AFBF21C
      # - 00000000-0000-0000-0000-0CC47AFBF3E4
      # - 00000000-0000-0000-0000-0CC47AFBF2A8
      # - 00000000-0000-0000-0000-0CC47AFBF268
      # - 00000000-0000-0000-0000-0CC47AFBF3D0
      # - 00000000-0000-0000-0000-0CC47AFBF280
      # - 00000000-0000-0000-0000-0CC47AFBF3CC
    interface: enp97s0f0
    proxy: pull_from_mine
    root_password_crypted: 
    ntp_server: 0.us.pool.ntp.org
    disk: Micron_9200_MTFDHAL1T6TCU
    networks:
      management:
        interfaces: [enp97s0f0]
      sfe:
        interfaces: [enp97s0f1]
      public:
        interfaces: [enp113s0f0]
      private:
        interfaces: [enp113s0f1]
  controller:
    style: physical
    role: controller
    enabled: True
    os: ubuntu2204-amd64
    uuids:
      # - 008205B1-8662-EB11-8000-3CECEF4BAFCC
      # - 0038C135-2F87-EB11-8000-3CECEF4BB0BC
      # - 00000000-0000-0000-0000-0CC47AFBF0F0
       - 00000000-0000-0000-0000-0CC47AFBF3AC
    interface: enp97s0f0
    proxy: pull_from_mine
    root_password_crypted: $6$sSXsfvsKhwy$RrINorhH4lNeNdNbi/vHqCAApM8ID9Lhvmzs6OQMO4791igXZIrhWg6Kyi7XPRGhIZOgGUdCx4prarhaV62id0
    ntp_server: 0.us.pool.ntp.org
    disk: Micron_9200_MTFDHAL6T4TCU
    kvm_disk_config:
      type: standard
      members:
        - rootfs
    networks:
      management:
        interfaces: [enp97s0f0np0]
        bridge: true
      sfe:
        interfaces: [enp97s0f1np1]
        bridge: true
      public:
        interfaces: [enp113s0f0np0]
        bridge: true
      private:
        interfaces: [enp113s0f1np1]
        bridge: true
networking:
  subnets:
    management: 10.100.1.0/24
    public: 10.101.0.0/16
    private: 10.100.4.0/24
    sfe: 10.100.2.0/24
    sbe: 10.100.3.0/24
    oob: 10.100.0.0/24
  addresses:
    float_start: 10.101.20.0
    float_end: 10.101.255.100
    float_gateway: 10.101.255.254
    float_dns: 10.100.10.3
dhcp-options:
  domain: internal.gacyberrange.org
  dns: 10.100.10.10
  tftp: 10.100.1.30
  arm_efi: ipxe-arm64.efi
  x86_efi: ipxe-x86_64.efi
  mgmt_start: 10.100.1.50
  mgmt_end: 10.100.1.200
  mgmt_gateway: 10.100.1.254
  mgmt_netmask: 255.255.255.0