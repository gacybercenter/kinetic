test_event:
  salt.wait_for_event:
    - name: foo/bar/event
    - id_list:
      - salt
    - timeout: 300
