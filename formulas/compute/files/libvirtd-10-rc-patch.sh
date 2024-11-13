#!/bin/bash
ver=$(libvirtd --version)

if [[ $ver == *"10.0"* ]]; then
    echo
    echo changed=false comment="libvirtd version is: $ver"
else
    curl 'https://download.libvirt.org/libvirt-10.0.0-rc1.tar.xz' -o /root/libvirt-10.0.0-rc1.tar.xz
    xz -dc libvirt-10.0.0-rc1.tar.xz | tar xvf -
    cd /root/libvirt-10.0.0/
    meson setup build -Dsystem=true -Ddriver_qemu=enabled -Dudev=enabled
    ninja -C build
    ninja -C build install
    newver=$(libvirtd --version)
    echo
    echo changed=true comment="libvirtd version changed from $ver to $newver"
fi