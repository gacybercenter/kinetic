include:
  - /formulas/k8s-logger/configure

fluent-bit-repo:
  pkgrepo.managed:

fluent-bit-pkg:
  pkg.installed:
    - name: fluent-bit