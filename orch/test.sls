reboot_cache:
  salt.function:
    - tgt: 'cache*'
    - name: system.reboot
    - kwargs:
        at_time: 1
