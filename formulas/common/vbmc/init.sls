install_python_pip:
  pkg.installed:
    - name: python3-pip

install_python_virtualenv:
  pkg.installed:
    - name: python3-virtualenv
    - require:
      - pkg: install_python_pip

# Create virtual environment
virtualbmc_venv:
  virtualenv.managed:
    - name: /opt/virtualbmc
    - venv_bin: /usr/bin/virtualenv
    - python: /usr/bin/python3
    - system_site_packages: False
    - require:
      - pkg: install_python_virtualenv

# Install virtualbmc in virtualenv
install_virtualbmc:
  pip.installed:
    - name: virtualbmc
    - bin_env: /opt/virtualbmc
    - require:
      - virtualenv: virtualbmc_venv

# Create configuration directory
virtualbmc_config_dir:
  file.directory:
    - name: /etc/virtualbmc
    - user: root
    - group: root
    - mode: 755

# Manage virtualbmc.conf
virtualbmc_config:
  file.managed:
    - name: /etc/virtualbmc/virtualbmc.conf
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [default]
        config_dir = /etc/virtualbmc
        pid_file = /var/run/vbmcd.pid
        auto_start = true

        [log]
        debug = true
        logfile = /var/log/vbmcd.log

        [ipmi]
        session_timeout = 30
    - require:
      - file: virtualbmc_config_dir

# Manage systemd service file
vbmcd_service_file:
  file.managed:
    - name: /etc/systemd/system/vbmcd.service
    - user: root
    - group: root
    - mode: 644
    - contents: |
        [Unit]
        Description=VirtualBMC Daemon
        After=network.target libvirtd.service

        [Service]
        ExecStart=/opt/virtualbmc/bin/vbmcd --foreground
        Environment="VIRTUALBMC_CONFIG=/etc/virtualbmc/virtualbmc.conf"
        Restart=on-failure
        User=root
        Group=root

        [Install]
        WantedBy=multi-user.target

# Reload systemd daemon
systemd_daemon_reload:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: vbmcd_service_file

# Manage vbmcd service
vbmcd_service:
  service.running:
    - name: vbmcd
    - enable: True
    - require:
      - pip: install_virtualbmc
      - file: vbmcd_service_file
      - cmd: systemd_daemon_reload
    - watch:
      - file: vbmcd_service_file
      - file: virtualbmc_config
      - cmd: systemd_daemon_reload