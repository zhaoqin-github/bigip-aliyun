#!/bin/bash -e

mkdir -p /tmp/$$

guestfish -a "$1" <<EOF
  run
  mount /dev/vg-db-vda/set.1.root /
  mount /dev/vg-db-vda/dat.share /shared
  download /shared/vadc/.hypervisor_type /tmp/$$/.hypervisor_type
  ! sed -i "s/HYPERVISOR=0/HYPERVISOR=alibaba/g" /tmp/$$/.hypervisor_type
  upload /tmp/$$/.hypervisor_type /shared/vadc/.hypervisor_type
  exit
EOF

rm -rf /tmp/$$
