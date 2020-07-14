{% set type = pillar['type'] %}

{{ type }}_waiting_room_sleep:
  salt.runner:
    - name: test.sleep
    - kwarg:
        s_time: 1
