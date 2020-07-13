thorium_tester:
  reg.list:
    - add: qux
    - match: foo/bar/baz
    - stamp: True
    
register:
  file.save
