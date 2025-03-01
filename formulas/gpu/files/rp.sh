#!/bin/bash

wget http://cache.dev.gacyberrange.org:3142/repository/nvidia-550/nvidia-vgpu-ubuntu-aie-550_550.144.02_amd64.deb
dpkg -i nvidia-vgpu-ubuntu-aie-550_550.144.02_amd64.deb

cloud="--os-cloud kinetic"
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _e1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_80C $i; done
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _c1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_40C $i; done
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _a1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_40C $i; done

for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _81_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_20C $i; done