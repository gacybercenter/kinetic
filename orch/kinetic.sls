accept_pxe_key:
  salt.function:
    - name: file.move
    - tgt: 'salt'
    - arg:
      - /etc/salt/pki/master/minions_pre/pxe
      - /etc/salt/pki/master/minions/pxe

