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

# Get current project list in the specified keystone domain and save to /tmp/ldap_projects
openstack project list --domain ldap > /tmp/ldap_projects
openstack user list --domain ldap | grep -P '[[:alnum:]]{64}' | awk '{ print $4 }' | while read uid
do
  project_test=$(grep $uid /tmp/ldap_projects)
  if [[ $project_test != '' ]]; then
    echo -n 'Existing '
    echo -n $uid
    echo ' project detected...skipping creation...'
    echo $project_test
  else
    openstack project create $uid --domain ldap
    openstack role add --user $uid --user-domain ldap --project $uid --project-domain ldap user
  fi
done

# Cleanup
rm /tmp/ldap_projects
