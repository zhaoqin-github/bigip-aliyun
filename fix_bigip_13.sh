#!/bin/bash -e

mkdir -p /tmp/$$

guestfish -a "$1" <<EOF
  run
  mount /dev/vg-db-hda/set.1.root /
  mount /dev/vg-db-hda/set.1._usr /usr
  download /etc/vadc-init/cloudinit-prepare /tmp/$$/cloudinit-prepare
  ! sed -i "s/CI_DATASOURCE='ConfigDrive'/CI_DATASOURCE='Ec2'/g" /tmp/$$/cloudinit-prepare
  upload /tmp/$$/cloudinit-prepare /etc/vadc-init/cloudinit-prepare
  download /defaults/config/templates/cloud-init.tmpl /tmp/$$/cloud-init.tmpl
  ! sed -i "s/169.254.169.254/100.100.100.200/g" /tmp/$$/cloud-init.tmpl
  upload /tmp/$$/cloud-init.tmpl /defaults/config/templates/cloud-init.tmpl
  download /usr/lib/python2.6/site-packages/cloudinit/sources/DataSourceEc2.py /tmp/$$/DataSourceEc2.py
  ! sed -i "s/2009-04-04/2016-01-01/g" /tmp/$$/DataSourceEc2.py
  upload /tmp/$$/DataSourceEc2.py /usr/lib/python2.6/site-packages/cloudinit/sources/DataSourceEc2.py
  exit
EOF

rm -rf /tmp/$$
