reboot_cache:
  salt.function:
    - tgt: 'cache*'
    - name: system.reboot
    - at_time: 1
