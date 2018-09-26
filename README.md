# kinetic

Kinetic is a deployment and maintenance tool for Cyber Ranges originally developed at the US Army Cyber School at Fort Gordon, Georgia.  The core components are [salt](https://www.saltstack.com/), [openstack](https://www.openstack.org), and [ceph](https://ceph.com/).

Kinetic is currently in the middle of being converted from a bespoke, single environment solution to a framework - it is not ready for production and pointing your environment at our master branch will break
everything.  The creation of the version 1.0 tag will indicate that kinetic is production ready.

Kinetic is designed to make the deployment and maintenance of cyber ranges easy and code-driven.  Every piece of the infrastructure is 100% reproducible and zero touch after your initial 
out-of-the-box hardware config (UEFI, etc.).  You configure your local pillar appropriately, start the salt orchestrate runner, and you're done.

The various heat templates that power scenarios all use a standard naming convention.  Sticking to this naming convention (instances, networks, images, etc.) mean that templates can be
shared across organizations.

## Prerequisites

There are two critical repositories that are required for a successful kinetic deployment:

1. A repository containing the kinetic codebase that is used as a [gitfs fileserver for salt](https://docs.saltstack.com/en/latest/topics/tutorials/gitfs.html) (usually just pointing at a release/tag/branch on this github repository)
2. A repository containing your site-specific configuration information that is used as a [gitfs pillar for salt](https://docs.saltstack.com/en/latest/ref/pillar/all/salt.pillar.git_pillar.html#git-pillar-configuration). (This can be stored anywhere. [Secrets should be encrypted using the salt pillar gpg renderer](https://docs.saltstack.com/en/latest/ref/renderers/all/salt.renderers.gpg.html))

Additionally, you need to ensure that:

1. All hosts (cache, compute, controller, storage, zun-compute) have their firmare AND option ROMs in UEFI-only mode.
2. You have designed your subnetting scheme to support all required networks (public, private, management, storage frontend, storage backend, out-of-band)
  * salt master - management
  * cache - management, public
  * controller - management, storage frontend, private, public
  * compute - management, storage frontend, private, public
  * storage - management, storage frontend, storage backend
  * zun-compute - management, storage frontend, private, public
3. You have a fresh installation of Debian Stretch.
You will have to ensure that this machine has an interface on the management network.
This is the host on which you will run ```bootstrap.sh```.
This machine will be your salt master.
4. All hosts can reach your salt master on TCP 4505/4506.  There is no need for the master to be able to reach the hosts.  Salt has a pubsub architecture.

## Recommendations

Kinetic is desiged to be used on larger environments that have multiples of the same type of hardware performing the same purpose, e.g. your purchasing department bought 50 compute nodes, 50 storage nodes, 
and 6 controller nodes at the same time, so they all have the same configuration amongst themselves.  That's not to say that it *can't* be used with hardware that you find randomly and slap together, its
just going to be a pain.

Kinetic is *not* designed to provide upgrade paths.  When new major releases come out upstream, you roll your entire infrastructure.  If you follow the kinetic commandments, this will not matter to you and
will make your life much easier in the long run.

While the cache is optional, it is *highly* recommended that you use it.  Trying to launch 50 stacks simultaneously for a class will almost certainly get you throttled upstream as you download and install packages.

