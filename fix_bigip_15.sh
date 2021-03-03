#!/bin/bash -e

mkdir -p /tmp/$$

cat > /tmp/$$/alibaba-init.patch <<EOF
@@ -22,6 +22,8 @@
 TMP_PUB_KEY_INDICES="/tmp/pub-key-indices"
 fetch_ssh_key=0

+ALIBABA_FIRST_BOOT=0
+
 ATTEMPTS=5
 FAILED=0

@@ -68,6 +70,9 @@
     if [ \$DEBUG -ge 1 ]; then
         show_dhcp_settings
     fi
+
+    ALIBABA_FIRST_BOOT=1
+
     # Remove the marker on 1st boot:
     rm -f \$VADC_FIRST_BOOT
     rc=\$?
@@ -137,6 +142,16 @@
     if [ \$rc -ne 0 ]; then ret_stat=\$RC_FAIL; fi
 fi

+if [ \$ALIBABA_FIRST_BOOT -eq 1 ] ; then
+    if [ -x /etc/vadc-init/alibaba-userdata ] ; then
+        log_echo "Execute customized userdata script."
+        /etc/vadc-init/alibaba-userdata >/tmp/alibaba-userdata.log 2>&1 &
+    elif [ -x /etc/vadc-init/default-alibaba-userdata ] ; then
+        log_echo "Execute default userdata script."
+        /etc/vadc-init/default-alibaba-userdata >/tmp/default-alibaba-userdata.log 2>&1 &
+    fi
+fi
+
 if [ \$ret_stat -ne \$RC_OK ]; then
     echo "[  FAILED  ]"
     dbg_print_delimiter
EOF

cat > /tmp/$$/default-alibaba-userdata <<EOF
#!/bin/bash -x

##########################################################################
# Block until mcpd is completely initialized and ready to accept commands.
function wait_until_mcpd_is_initialized() {
    local retries

    for retries in {1..60} ; do
        # Retry until mcpd completes startup:
        /usr/bin/tmsh -a show sys mcp-state field-fmt 2>/dev/null | grep phase | grep running
        rc=\$?
        if [ \$rc -eq 0 ]; then break ; fi
        echo "wait_until_mcpd_is_initialized - retries #\$retries"
        echo \$(/usr/bin/tmsh -a show sys mcp-state field-fmt | grep "last-load")
        sleep 10
    done

    if [ \$rc -ne 0 ]; then
        echo "wait_until_mcpd_is_initialized - mcpd hasn't completed initialization"
        # Extra debug output:
        /usr/bin/tmsh -a show sys mcp-state field-fmt
        /usr/bin/tmsh -a load sys config
        /usr/bin/tmsh -a load sys config default
    fi
}
##########################################################################

METADATA_URL="http://100.100.100.200/2016-01-01/meta-data"
USERDATA_URL="http://100.100.100.200/2016-01-01/user-data"
CURL="curl -s -m5"

USERDATA=\$(\${CURL} \${USERDATA_URL})

if [[ -n "\${USERDATA}" ]] ; then
  echo "Customized userdata is input via API. Skip default userdata script."
  exit 0
fi

wait_until_mcpd_is_initialized

BIGIP_HOSTNAME=\$(\${CURL} \${METADATA_URL}/hostname)
if [[ -n "\${BIGIP_HOSTNAME}" ]] ; then
  if ! [[ "\${BIGIP_HOSTNAME}" == *.* ]] ; then
    BIGIP_HOSTNAME=\${BIGIP_HOSTNAME}.localdomain
  fi
  tmsh modify /sys global-settings hostname \${BIGIP_HOSTNAME}
fi

BIGIP_NTP=\$(\${CURL} \${METADATA_URL}/ntp-conf/ntp-servers | sed "s/\r$//g")
if [[ -n "\${BIGIP_NTP}" ]] ; then
  tmsh modify /sys ntp servers add { \${BIGIP_NTP} }
fi

BIGIP_DNS=\$(\${CURL} \${METADATA_URL}/dns-conf/nameservers | sed "s/\r$//g")
if [[ -n "\${BIGIP_DNS}" ]] ; then
  tmsh modify /sys dns name-servers add { \${BIGIP_DNS} }
fi

tmsh modify /sys global-settings gui-setup disabled
tmsh modify /sys db configsync.allowmanagement value enable
tmsh modify /sys ntp timezone Asia/Shanghai
tmsh save /sys config

touch /tmp/default-alibaba-userdata.done
EOF

guestfish -a "$1" <<EOF
  run
  mount /dev/vg-db-vda/set.1.root /
  mount /dev/vg-db-vda/dat.share /shared
  mount /dev/vg-db-vda/set.1._config /config
  write /shared/vadc/.hypervisor_type "HYPERVISOR=alibaba\n"
  write /config/tmm_init.tcl "device driver vendor_dev 1af4:1000 sock\n"
  selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts /config/tmm_init.tcl
  download /etc/vadc-init/alibaba-init /tmp/$$/alibaba-init
  ! patch -s /tmp/$$/alibaba-init /tmp/$$/alibaba-init.patch
  upload /tmp/$$/alibaba-init /etc/vadc-init/alibaba-init
  upload /tmp/$$/default-alibaba-userdata /etc/vadc-init/default-alibaba-userdata
  chmod 0755 /etc/vadc-init/default-alibaba-userdata
  selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts /etc/vadc-init/default-alibaba-userdata
  sync
  exit
EOF

rm -rf /tmp/$$
