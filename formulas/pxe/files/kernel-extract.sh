#!/bin/bash
mount /srv/tftp/jammy/ubuntu2204.iso /mnt/
cp -af /mnt/casper/vmlinuz /srv/tftp/jammy/vmlinuz
cp -af /mnt/casper/initrd /srv/tftp/jammy/initrd
umount  /mnt