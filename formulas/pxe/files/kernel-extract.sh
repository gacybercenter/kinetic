#!/bin/bash
mount /srv/tftp/jammy/ubuntu2204.iso /mnt/
cp /mnt/casper/vmlinuz /srv/tftp/jammy/vmlinuz
cp /mnt/casper/initrd /srv/tftp/jammy/initrd
umount  /mnt