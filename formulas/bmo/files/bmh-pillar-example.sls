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
    root_password_crypted: $6$sSXsfvsKhwy$RrINorhH4lNeNdNbi/vHqCAApM8ID9Lhvmzs6OQMO4791igXZIrhWg6Kyi7XPRGhIZOgGUdCx4prarhaV62id0
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