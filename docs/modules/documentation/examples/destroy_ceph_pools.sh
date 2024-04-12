#!/bin/bash
ceph tell mon.* injectargs --mon_allow_pool_delete true
ceph osd pool delete vms vms --yes-i-really-really-mean-it
ceph osd pool delete images images --yes-i-really-really-mean-it
ceph osd pool delete volumes volumes --yes-i-really-really-mean-it
ceph osd pool delete device_health_metrics device_health_metrics --yes-i-really-really-mean-it
ceph osd pool delete .rgw.root .rgw.root  --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.log default.rgw.log --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.control default.rgw.control --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.meta default.rgw.meta --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.meta default.rgw.meta --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.buckets.index default.rgw.buckets.index --yes-i-really-really-mean-it
ceph osd pool delete default.rgw.buckets.data default.rgw.buckets.data --yes-i-really-really-mean-it
ceph tell mon.* injectargs --mon_allow_pool_delete false