qemu-kvm:
  pkg.installed

qemu-utils:
  pkg.installed

genisoimage:
  pkg.installed

libvirt-clients:
  pkg.installed

libvirt-daemon-system:
  pkg.installed

mdadm:
  pkg.installed:
    - reload_modules: True

xfsprogs:
  pkg.installed

bridge-utils:
  pkg.installed

python3-libvirt:
  pkg.installed
