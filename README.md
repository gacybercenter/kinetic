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
  * cache - management, public
  * controller - management, storage frontend, private, public
  * compute - management, storage frontend, private, public
  * storage - management, storage frontend, storage backend
  * zun-compute - management, storage frontend, private, public
3. You have a fresh installation of Debian Stretch on a machine that has at least 8G of RAM.
This machine needs to have [bridging](https://www.cyberciti.biz/faq/how-to-configuring-bridging-in-debian-linux/) configured already.
You will have to pass the bridge interface name to ```bootstrap.sh.```
This host will run your salt master as well as your pxe server.
This is the host on which you will run ```bootstrap.sh```.
Both the salt master and tftp will run in separate kvm virtual machines.
4. All hosts can reach your salt master on TCP 4505/4506.  There is no need for the master to be able to reach the hosts.  Salt has a pubsub architecture.
5. Your dhcp server is issuing ipxe.efi as the efi 64 bit boot filename and next-server is set to pxe
*NOTE* If your dhcp server does not support issuing hostname as next-server,
you will need to create your own tftp server and have it issue [this](fixme) file.
your system will automatically compile a fresh copy of this for you from source if you do not wish to use the pre-compiled version.
The freshly compiled version will be located at /var/www/html/ipxe.efi on your pxe server once it is fully highstated.
6. DHCP clients can successfully register their leases in your local DNS resolver.
7. All hosts can reach your pxe server on UDP 69 and TCP 80.  Your tftp server must be able to reach your hosts on ANY UDP port as well.

## Recommendations

Kinetic is desiged to be used on larger environments that have multiples of the same type of hardware performing the same purpose, e.g. your purchasing department bought 50 compute nodes, 50 storage nodes, 
and 6 controller nodes at the same time, so they all have the same configuration amongst themselves.  That's not to say that it *can't* be used with hardware that you find randomly and slap together, its
just going to be a pain.

Kinetic is *not* designed to provide upgrade paths.  When new major releases come out upstream, you roll your entire infrastructure.  If you follow the kinetic commandments, this will not matter to you and
will make your life much easier in the long run.

While the cache is optional, it is *highly* recommended that you use it.  Trying to launch 50 stacks simultaneously for a class will almost certainly get you throttled upstream as you download and install packages.

## Quick Start

On your configured Debian host, run:
```
curl https://raw.githubusercontent.com/georgiacyber/kinetic/master/bootstrap/bootstrap.sh |  
bash -s -- -i {{ interface }} -f {{ gitfs file root}} -p {{ pillar }} -k {{ key }}
```

where

```{{ interface }}``` = the name of the bridged management interface that you have configured on your debian host, e.g. mgmt.

```{{ gitfs file root}}``` = the repository from which you wish to source the kinetic static files.

```{{ pillar }}``` = the repository from which you wish to source your site-specific configuration.

```{{ key }}``` = the key that you will use to log in to your salt master and pxe server after they boot.
Example:

```
curl https://raw.githubusercontent.com/georgiacyber/kinetic/master/bootstrap/bootstrap.sh |
bash -s -- -i mgmt \
-f https://github.com/GeorgiaCyber/kinetic.git \
-p https://github.com/GeorgiaCyber/kinetic-pillar-sample.git \
-k "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKw+cBx9BBKcoXKLxMLVoGCD7znZqBjnMkaIipAikQJ"
```

As the script completes, you should see a message stating that both pxe and salt have been created from their respective
config.xml files by virsh.  You can track their bootstrap process with ```tail /kvm/vms/*/console.log```.
Once you see a message on both hosts that cloud-init has finished with the NoCloud datasource, you can log in to
both with the corresponding private key to the public key you specific in your bootstrap script as the root user.
Log in to salt first:

```ssh root@salt```

Once you're in the salt master, check for the presences of 2 as-yet unaccepted keys:
```
root@salt:~# salt-key
Accepted Keys:
Denied Keys:
Unaccepted Keys:
pxe
salt
Rejected Keys:
```

If you see both pxe and salt in the unaccepted list, the bootstrap was successful.  Go ahead and accept the keys:
```
salt-key -A
```

At this point you should be able to communicate with both of your minions via your salt master:
```
root@salt:~# salt \* test.ping
pxe:
    True
salt:
    True
```

The next thing you will want to do is highstate your salt master so it can be fully configured and reach to orchestrate the rest of your environment:

```
salt salt state.highstate
```

This command will likely end with an error stating ```Authentication error occurred```.  That's OK - we made changes to the master configuration
that caused the master daemon to restart, so it couldn't return the results properly.  If you run an additional highstate, you will see that
the configurations were successfully applied.
