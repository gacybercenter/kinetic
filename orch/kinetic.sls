accept_pxe_key:
  salt.function:
    - name: file.copy
    - tgt: 'salt'
    - kwarg:
        remove_existing: true
        source: /etc/salt/pki/master/minions_pre/pxe
        name: /etc/salt/pki/master/minions/pxe
        creates: /etc/salt/pki/master/minions/pxe
