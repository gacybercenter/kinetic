#!/bin/bash

export OS_USERNAME=admin
export OS_PASSWORD={{ admin_password }}
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL={{ internal_endpoint }}
export OS_IDENTITY_API_VERSION=3

today=`date +%s`
startdate=`date +%s -d {{ start }}`
enddate=`date +%s -d {{ end }}`
maxstudents=$(({{number_of_students}}-1))
maxinstructors=$(({{number_of_instructors}}-1))
subpassword={{ default_password }}
subpassword=${subpassword:0:10}
urltemplate={{ template }}
echo "urltemplate:($urltemplate)"

openstack user list > /tmp/openstackuserlist
if [ $? -ne 0 ]; then
  echo "ERROR: Openstack Command Error"
  exit
fi
echo "INFO: {{ class }} $today $startdate $enddate - Created the openstack user list and checking the class dates"
if [ $today -lt $startdate ]; then
  #before start date create class
  if [ `cat /tmp/openstackuserlist | grep {{ class }} -c` -eq 0 ]; then
    #create only if it doesn't exist
    echo "INFO: CREATING {{ class }} - Creating Students and Instructors"
    for students in $(seq -w 00 $maxstudents)
    do
      export OS_USERNAME=admin
      export OS_PASSWORD={{ admin_password }}
      export OS_PROJECT_NAME=admin
      export OS_USER_DOMAIN_NAME=Default
      export OS_PROJECT_DOMAIN_NAME=Default
      export OS_AUTH_URL={{ internal_endpoint }}
      export OS_IDENTITY_API_VERSION=3
      openstack user create {{ class }}-student-$students --password {{ default_password }} --or-show
      openstack project create {{ class }}-student-$students --or-show
      openstack role add --project {{ class }}-student-$students --user {{ class }}-student-$students user
      if [ "$urltemplate" != "None" ]; then
        export OS_USERNAME={{ class }}-student-$students
        export OS_PASSWORD={{ default_password }}
        export OS_PROJECT_NAME={{ class }}-student-$students
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL={{ internal_endpoint }}
        export OS_IDENTITY_API_VERSION=3
        # sid=$students the sid++ code errors on 08 and 09
        # let sid++
        # echo "sid: $sid"
        # master yaml takes last_name and password while windows yaml also takes the student_id
        openstack stack create --template {{ template }} --enable-rollback --wait stack-{{ class }}-student-$students
      fi
    done
    for instructors in $(seq -w 00 $maxinstructors)
    do
      export OS_USERNAME=admin
      export OS_PASSWORD={{ admin_password }}
      export OS_PROJECT_NAME=admin
      export OS_USER_DOMAIN_NAME=Default
      export OS_PROJECT_DOMAIN_NAME=Default
      export OS_AUTH_URL={{ internal_endpoint }}
      export OS_IDENTITY_API_VERSION=3
      openstack user create {{ class }}-instructor-$instructors --password {{ default_password }} --or-show
      openstack project create {{ class }}-instructor-$instructors --or-show
      openstack role add --project {{ class }}-instructor-$instructors --user {{ class }}-instructor-$instructors user
      if [ "$urltemplate" != "None" ]; then
        export OS_USERNAME={{ class }}-instructor-$instructors
        export OS_PASSWORD={{ default_password }}
        export OS_PROJECT_NAME={{ class }}-instructor-$instructors
        export OS_USER_DOMAIN_NAME=Default
        export OS_PROJECT_DOMAIN_NAME=Default
        export OS_AUTH_URL={{ internal_endpoint }}
        export OS_IDENTITY_API_VERSION=3
        # iid=$instructors the iid++ code errors on 08 and 09
        # let iid++
        # echo "iid: $iid"
        # master yaml takes last_name and password while windows yaml also takes the student_id
        openstack stack create --template {{ template }} --enable-rollback --wait stack-{{ class }}-instructor-$instructors
      fi
    done
  fi
elif [ $today -gt $enddate ]; then
    # delete class resources if today is after end date
    echo "INFO: DELETE Today is past end date"
    if [ `cat /tmp/openstackuserlist | grep {{ class }} -c` -gt 0 ]; then
      # delete only if users exist
      echo "  INFO: **** {{ class }} - Delete the class - students, instructors, instances"
      export OS_USERNAME=admin
      export OS_PASSWORD={{ admin_password }}
      export OS_PROJECT_NAME=admin
      export OS_USER_DOMAIN_NAME=Default
      export OS_PROJECT_DOMAIN_NAME=Default
      export OS_AUTH_URL={{ internal_endpoint }}
      export OS_IDENTITY_API_VERSION=3
      for students in $(seq -w 00 $maxstudents)
      do
        ins="{{ class }}-student-$students"
        echo "  INFO: To be deleted $ins"
        # delete the stack that was automatically created for students
        #openstack stack delete -y --wait stack-{{ class }}-student-$students
        # purge the project Networks,Subnets,Ports,Router interfaces,Routers,Floating IP addresses,Security groups
        # neutron purge is being depricated, but currently does not have an equivalent openstack command
        #neutron purge {{ class }}-student-$students
        # purge the project instances, volumes, images
        #openstack project purge --project {{ class }}-student-$students
        # delete the user
        #openstack user delete {{ class }}-student-$students
      done
      for instructors in $(seq -w 00 $maxinstructors)
      do
        ins="{{ class }}-instructor-$instructors"
        echo "  INFO: To be deleted $ins"
        # delete the stack that was automatically created for instructors
        #openstack stack delete -y --wait stack-{{ class }}-instructor-$instructors
        # purge the project Networks,Subnets,Ports,Router interfaces,Routers,Floating IP addresses,Security groups
        # neutron purge is being depricated, but currently does not have an equivalent openstack command
        #neutron purge {{ class }}-instructor-$instructors
        # purge the project instances, volumes, images
        #openstack project purge --project {{ class }}-instructor-$instructors
        # delete the user
        #openstack user delete {{ class }}-student-$students
      done
    fi
else
    echo "INFO: NOTHING TO DO FOR {{ class }}"
fi
echo "INFO: Removing temp user list"
rm /tmp/openstackuserlist
