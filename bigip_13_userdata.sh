#!/bin/bash -e

METADATA_URL="http://100.100.100.200/2016-01-01/meta-data"
CURL="curl -s"

WORK_DIR=/tmp
METADATA_JSON=${WORK_DIR}/aliyun_metadata.json
BIGIP_INIT=${WORK_DIR}/aliyun_bigip_init

# Fetch aliyun metadata.json

echo '{
 "hostname" : "'$(${CURL} ${METADATA_URL}/hostname)'",
 "ntp": "'$(${CURL} ${METADATA_URL}/ntp-conf/ntp-servers | tr -d "\r" | head -n1)'",
 "dns": "'$(${CURL} ${METADATA_URL}/dns-conf/nameservers | tr -d "\r" | head -n1)'"
}' > ${METADATA_JSON}


# Generate aliyun BIG-IP init script
get_metadata_prop() {
  cat ${METADATA_JSON} | jq -r .$1
}

BIGIP_HOSTNAME=$(get_metadata_prop "hostname")
if ! [[ ${BIGIP_HOSTNAME} == *.* ]] ; then
  BIGIP_HOSTNAME=${BIGIP_HOSTNAME}.localdomain
fi
BIGIP_NTP=$(get_metadata_prop "ntp")
BIGIP_DNS=$(get_metadata_prop "dns")

cat > ${BIGIP_INIT}.sh << EOF
#!/bin/bash -ex

timeout=121
while [[ \$timeout -gt 1 ]] ; do
  sleep 10
  ((timeout=timeout-10))
  state=\$(tmsh show /sys mcp 2>/dev/null | grep "Running Phase" | awk '{ print \$3 }')
  name=\$(tmsh list /sys global-settings hostname 2>/dev/null | grep hostname | awk '{ print \$2 }')
  if [[ \$state == running ]] && [[ \$name == bigip1 ]] ; then
    break
  fi
done

if [[ \$timeout -le 1 ]] ; then
  touch ${BIGIP_INIT}.timeout
  exit 1
fi

tmsh modify /sys global-settings gui-setup disabled
tmsh modify /sys db configsync.allowmanagement value enable
tmsh modify /sys global-settings hostname ${BIGIP_HOSTNAME}
tmsh modify /sys ntp timezone Asia/Shanghai
tmsh modify /sys ntp servers add { ${BIGIP_NTP} }
tmsh modify /sys dns name-servers add { ${BIGIP_DNS} }
tmsh save /sys config

touch ${BIGIP_INIT}.done
EOF

chmod +x ${BIGIP_INIT}.sh

# Execute aliyun BIG-IP init script

${BIGIP_INIT}.sh >${BIGIP_INIT}.log 2>&1 &

touch /tmp/aliyun_userdata.done
