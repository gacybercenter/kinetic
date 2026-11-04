# Horizon has no host packages. The chart comes from the OpenStack Helm
# repo, same as Heat. The release itself is in configure.sls.
include:
  - /formulas/osh-helm-repos/configure
