#!/bin/bash



cloud="--os-cloud kinetic"
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _e1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_80C $i; done
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _c1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_40C $i; done
for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _a1_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_40C $i; done

for i in $(openstack $cloud resource provider list -c uuid -c name -f value|grep _81_ | awk '{print $1}'); do openstack $cloud resource provider trait set --trait CUSTOM_NVIDIA_20B5_A100D_20C $i; done