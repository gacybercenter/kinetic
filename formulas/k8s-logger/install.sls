include:
  - /formulas/k8s-logger/configure

{% from "fluent-bit/map.jinja" import fluent_bit with context %}

fluent-bit-pkg:
  pkg.installed:
    - name: {{ fluent_bit.pkg }}