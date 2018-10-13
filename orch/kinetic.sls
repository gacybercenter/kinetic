master_setup:
  salt.state:
    - tgt: 'salt'
    - highstate: true
