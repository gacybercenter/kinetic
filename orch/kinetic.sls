accept_pxe_key:
  salt.function:
    - name: file.copy
    - tgt: 'salt'
    - arg:
      - /etc/salt/pki/master/minions_pre/pxe
      - /etc/salt/pki/master/minions/pxe
    - remove_existing: true
