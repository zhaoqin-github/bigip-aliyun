#!/bin/bash -x

##########################################################################
# Block until mcpd is completely initialized and ready to accept commands.
function wait_until_mcpd_is_initialized() {
    local retries

    for retries in {1..60} ; do
        # Retry until mcpd completes startup:
        /usr/bin/tmsh -a show sys mcp-state field-fmt 2>/dev/null | grep phase | grep running
        rc=$?
        if [ $rc -eq 0 ]; then break ; fi
        echo "wait_until_mcpd_is_initialized - retries #$retries"
        echo $(/usr/bin/tmsh -a show sys mcp-state field-fmt | grep "last-load")
        sleep 10
    done

    if [ $rc -ne 0 ]; then
        echo "wait_until_mcpd_is_initialized - mcpd hasn't completed initialization"
        # Extra debug output:
        /usr/bin/tmsh -a show sys mcp-state field-fmt
        /usr/bin/tmsh -a load sys config
        /usr/bin/tmsh -a load sys config default
        exit 1
    fi
}
##########################################################################

MEATADATA="/run/cloud-init/instance-data.json"

if [[ ! -r ${MEATADATA} ]] ; then
  echo "Fail to load ${MEATADATA}"
  exit 1
fi

wait_until_mcpd_is_initialized

BIGIP_HOSTNAME=$(cat ${MEATADATA} | jq -r '.ds."meta-data".hostname')

if ! [[ "${BIGIP_HOSTNAME}" == *.* ]] ; then
  BIGIP_HOSTNAME=${BIGIP_HOSTNAME}.localdomain
fi

if [[ -n "${BIGIP_HOSTNAME}" ]] ; then
  echo "modify device name"
  tmsh modify /sys global-settings hostname ${BIGIP_HOSTNAME}
  tmsh mv cm device bigip1 ${BIGIP_HOSTNAME}
  if [ -f /config/httpd/conf/ssl.key/server.key ] && [ -f /config/httpd/conf/ssl.crt/server.crt ] ; then
    echo "renew device certificate"
    openssl req -rand /dev/random -new -key /config/httpd/conf/ssl.key/server.key -x509 -days 3650 -out /config/httpd/conf/ssl.crt/server.crt \
      -subj "/C=--/ST=WA/L=Seattle/O=MyCompany/OU=MyOrg/CN=${BIGIP_HOSTNAME}/emailAddress=root@${BIGIP_HOSTNAME}" -extensions usr_cert
  fi
fi

BIGIP_DNS=$(cat ${MEATADATA} | jq -r '.ds."meta-data"."dns-conf".nameservers[]')

if [[ -n ${BIGIP_DNS} ]] ; then
  echo "add dns servers"
  tmsh modify /sys dns name-servers add { ${BIGIP_DNS} }
fi

BIGIP_NTP=$(cat ${MEATADATA} | jq -r '.ds."meta-data"."ntp-conf"."ntp-servers"[]')
if [[ -n "${BIGIP_NTP}" ]] ; then
  echo "add ntp servers"
  tmsh modify /sys ntp servers add { ${BIGIP_NTP} }
fi

tmsh modify /sys db configsync.allowmanagement value enable
tmsh modify /sys global-settings gui-setup disabled
tmsh modify /sys ntp timezone Asia/Shanghai
tmsh save /sys config

# Activate BIG-IP at last
if [[ -r /tmp/license.key ]] ; then
  LIC_KEY=$(cat /tmp/license.key)
  INTERVAL=60
  RETRY=3
  while [[ ${RETRY} -gt 0 ]] ; do
    sleep ${INTERVAL}
    RESP=$(curl -s -u admin: -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d '{ "command": "install", "registrationKey": "'${LIC_KEY}'" }' http://localhost:8100/mgmt/tm/sys/license)
    CODE=$(echo "${RESP}" | tail -n1)
    if [[ ${CODE} -eq 200 ]] ; then
      RETRY=0
    else
      ((RETRY=RETRY-1))
    fi
  done
elif [[ -r /tmp/license.txt ]] ; then
  cp /tmp/license.txt /config/bigip.license
  reloadlic
elif [[ -r /tmp/license.json ]] ; then
  cat /tmp/license.json | jq -r .licenseText > /config/bigip.license
  reloadlic
fi

echo "setup complete"
