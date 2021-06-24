#!/bin/bash -e

guestfish -a "$1" <<EOF
  run
  mount /dev/vg-db-vda/set.1.root /
  mount /dev/vg-db-vda/dat.share /shared
  mount /dev/vg-db-vda/set.1._config /config
  write /shared/vadc/.hypervisor_type "HYPERVISOR=alibaba\n"
  write /config/tmm_init.tcl "device driver vendor_dev 1af4:1000 sock\n"
  selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts /config/tmm_init.tcl
  sync
  exit
EOF
