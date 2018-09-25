# kinetic

Kinetic is a deployment and maintenance tool for Cyber Ranges originally developed at the US Army Cyber School at Fort Gordon, Georgia.  The core components are salt, openstack, and ceph.

## Prerequisites

There are two critical repositories that are required for a successful kinetic deployment:

1. A repository containing the kinetic codebase that is used as a gitfs fileserver for salt (usually just pointing at a release on github)
2. A repository containing your site-specific configuration information that is used as a gitfs pillar for salt. (can be stored anywhere.  Secrets should be encrypted using the salt pillar gpg renderer)

Additionally, you need to ensure that:

1. All hosts (compute, controller, storage, zun-compute) have their firmare in UEFI-only mode.
2. You have designed your subnetting scheme to support all required networks (public, private, management, storage frontend, storage backend, out-of-band)
  * controller - management, storage frontend, private, public
  * compute - management, storage frontend, private, public
  * storage - management, storage frontend, storage backend
  * zun-compute - management, storage frontend, private, public
3. You have a running, unconfigured salt-master.  The normal master bootstrap install is fine:
 ```curl -L https://bootstrap.saltstack.com | sudo sh -s --- -M```
4. All hosts can reach your salt master on TCP 4505/4506.  There is no need for the master to be able to reach the hosts.  Salt has a pubsub architecture.
