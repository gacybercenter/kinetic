{% set type = data['path'] %}

publish pending id:
  runner.event.send:
    - args:
      - tag: foo/bar/baz
