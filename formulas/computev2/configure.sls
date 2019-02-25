include:
  - formulas/compute/configure

/etc/modprobe.d/kvm.conf:
  file.managed:
    - source: salt://formulas/computev2/files/kvm.conf
