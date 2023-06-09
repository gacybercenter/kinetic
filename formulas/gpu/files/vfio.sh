#!/bin/sh

PREREQ=""

prereqs()
{
   echo "$PREREQ"
}

case $1 in
prereqs)
   prereqs
   exit 0
   ;;
esac

for dev in {{ busid_gpu1 }} {{ busid_gpu2 }} {{ busid_gpu3 }} {{ busid_gpu4 }}
do
 echo "vfio-pci" > /sys/bus/pci/devices/$dev/driver_override
 echo "$dev" > /sys/bus/pci/drivers/vfio-pci/bind
done

exit 0
