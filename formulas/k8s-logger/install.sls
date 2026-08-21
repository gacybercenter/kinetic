{% set oscode = grains.get('oscodename') %}
include:
  - /formulas/k8s-logger/configure

fluent-bit-repo:
  pkgrepo.managed:
    - humanname: Fluent-Bit for {{ oscode }}
    - name: deb https://packages.fluentbit.io/ubuntu/{{ oscode }} {{ oscode }} main
    - dist: {{ oscode }}
    - file:  /etc/apt/sources.list.d/fluent-bit.list
    - key_url: https://packages.fluentbit.io/fluentbit.key
    - refresh: True


fluent-bit-pkg:
  pkg.installed:
    - name: fluent-bit