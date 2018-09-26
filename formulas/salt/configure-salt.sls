include:
  - /formulas/salt/install-salt

/etc/salt/master.d/default_top.conf:
  file.managed:
    - source: salt://formulas/salt/files/default_top.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/file_roots.conf:
  file.managed:
    - source: salt://formulas/salt/files/file_roots.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/fileserver_backend.conf:
  file.managed:
    - source: salt://formulas/salt/files/fileserver_backend.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/gitfs_pillar.conf:
  file.managed:
    - source: salt://formulas/salt/files/gitfs_pillar.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/gitfs_remotes.conf:
  file.managed:
    - source: salt://formulas/salt/files/gitfs_remotes.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/hash_type.conf:
  file.managed:
    - source: salt://formulas/salt/files/hash_type.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/interface.conf:
  file.managed:
    - source: salt://formulas/salt/files/interface.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/loop_interval.conf:
  file.managed:
    - source: salt://formulas/salt/files/loop_interval.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/ping_on_rotate.conf:
  file.managed:
    - source: salt://formulas/salt/files/ping_on_rotate.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/state_output.conf:
  file.managed:
    - source: salt://formulas/salt/files/state_output.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/top_file_merging_strategy.conf:
  file.managed:
    - source: salt://formulas/salt/files/top_file_merging_strategy.conf
    - source_hash: salt://formulas/salt/files/hash

/etc/salt/master.d/reactor.conf:
  file.managed:
    - source: salt://formulas/salt/files/reactor.conf
    - source_hash: salt://formulas/salt/files/hash
