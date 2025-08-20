# Install_Salt_Kubernetes_extension_for_helm:
#   pip.installed:
#     - pip_bin: /usr/bin/salt-pip
#     - name: saltext-kubernetes
# Install_k8s_python_sdk:
#   pip.installed:
#     - pip_bin: /usr/bin/salt-pip
#     - name: kubernetes
# Ensure wget is installed for downloading Helm
install_wget:
  pkg.installed:
    - name: wget

# Download Helm tarball
helm_download:
  cmd.run:
    - name: wget -O /tmp/helm-{{ pillar['helm_version'] }}.tar.gz {{ pillar['helm_url'] }}
    - unless: test -f /usr/local/bin/helm && helm version --short | grep {{ pillar['helm_version'] }}
    - require:
      - pkg: install_wget

# Verify checksum of downloaded file
helm_verify_checksum:
  cmd.run:
    - name: sha256sum /tmp/helm-{{ pillar['helm_version'] }}.tar.gz |grep {{ pillar['helm_checksum'] }} 
    - require:
      - cmd: helm_download
    - unless: test -f /usr/local/bin/helm && helm version --short | grep {{ pillar['helm_version'] }}

# Extract Helm tarball
helm_extract:
  archive.extracted:
    - name: /tmp/helm-{{ pillar['helm_version'] }}
    - source: /tmp/helm-{{ pillar['helm_version'] }}.tar.gz
    - user: root
    - group: root
    - require:
      - cmd: helm_verify_checksum
    - unless: test -f /usr/local/bin/helm && helm version --short | grep {{ pillar['helm_version'] }}

# Install Helm binary
helm_install:
  file.managed:
    - name: /usr/local/bin/helm
    - source: /tmp/helm-{{ pillar['helm_version'] }}/linux-amd64/helm
    - mode: 0755
    - user: root
    - group: root
    - require:
      - archive: helm_extract
    - unless: test -f /usr/local/bin/helm && helm version --short | grep {{ pillar['helm_version'] }}

# Clean up temporary files
helm_cleanup:
  file.absent:
    - names:
      - /tmp/helm-{{ pillar['helm_version'] }}.tar.gz
      - /tmp/helm-{{ pillar['helm_version'] }}
    - require:
      - file: helm_install