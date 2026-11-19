# Chart install is in configure.sls. This file is included so that SLS
# exists; an empty include fails rendering as whitespace-only.
runai_install:
  test.nop:
    - name: runai install
