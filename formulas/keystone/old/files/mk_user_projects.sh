## Copyright 2019 Augusta University
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

#!/bin/bash
## This script will enumerate the directory and identify all users that are part of the domain group.
## It will then iterate through that list one-by-one and test if a user project for that user exists.  If a
## project does exist, it will do nothing.  If a project does not exist, it will create it.  This script
## should be periodically run as part of a highstate as well as when new users are added to the system.
#!/bin/bash
export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

# Get current project list in the specified keystone domain and save to /tmp/{{ keystone_domain }}_projects
openstack project list --domain {{ keystone_domain }} > /tmp/{{ keystone_domain }}_projects
openstack user list --domain {{ keystone_domain }} | grep -P '[[:alnum:]]{64}' | awk '{ print $4 }' | while read uid
do
  project_test=$(grep $uid /tmp/{{ keystone_domain }}_projects)
  if [[ $project_test != '' ]]; then
    echo -n 'Existing '
    echo -n $uid
    echo ' project detected...skipping creation...'
    echo $project_test
  else
    openstack project create $uid --domain {{ keystone_domain }}
    openstack role add --user $uid --user-domain {{ keystone_domain }} --project $uid --project-domain {{ keystone_domain }} user
  fi
done

# Cleanup
rm /tmp/{{ keystone_domain }}_projects
