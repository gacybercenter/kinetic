reboot_cache:
  salt.function:
    - tgt: 'cache*'
    - name: system.reboot
    - kwarg:
        at_time: 1
