{% set type = data['path'].split('/')[5] %}

publish pending id:
  runner.event.send:
    - args:
      - tag: {{ type }}
