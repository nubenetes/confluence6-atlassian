#!/bin/bash
set -euo pipefail

# Setup Catalina Opts
: ${CATALINA_CONNECTOR_PROXYNAME:=}
: ${CATALINA_CONNECTOR_PROXYPORT:=}
: ${CATALINA_CONNECTOR_SCHEME:=http}
: ${CATALINA_CONNECTOR_SECURE:=false}

: ${CATALINA_OPTS:=}

CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyName=${CATALINA_CONNECTOR_PROXYNAME}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyPort=${CATALINA_CONNECTOR_PROXYPORT}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorScheme=${CATALINA_CONNECTOR_SCHEME}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorSecure=${CATALINA_CONNECTOR_SECURE}"

export CATALINA_OPTS

# Support Arbitrary User IDs (Reference: OpenShift Container Platform 3.9 Image Creation Guide):
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    #echo "${RUN_USER:-default}:x:$(id -u):0:${RUN_USER:-default} user:${CONFLUENCE_HOME}:/sbin/nologin" >> /etc/passwd
    echo "${RUN_USER:-default}:x:$(id -u):$(id -u):${RUN_USER:-default} user:${CONFLUENCE_HOME}:/sbin/nologin" >> /etc/passwd
  fi
  if [ -w /etc/group ]; then
    cp /etc/group /tmp/group
    sed -i "1s/.*/root:x:0:root,$(id -u),${RUN_USER:-default}/" /tmp/group
    > /etc/group
    cat /tmp/group >> /etc/group
  fi
  if [ -w /etc/profile ]; then
    cp /etc/profile /tmp/profile
    sed -i 's/umask 022/umask 002/' /tmp/profile
    > /etc/profile
    cat /tmp/profile >> /etc/profile
  fi 
fi
# End of Support Arbitrary User IDs


# https://confluence.atlassian.com/confkb/confluence-generates-confluence-is-vacant-error-on-install-779164449.html 
#if [ -w /etc/hosts ]; then
#  cp /etc/hosts /tmp/hosts
#  HOSTNAME=$(hostname)
#  sed -i '2s/.*/127.0.0.1 localhost ${HOSTNAME}/' /tmp/hosts
#  > /etc/hosts
#  cat /tmp/hosts >> /etc/hosts
#fi 

# Purge of confluence home:
# https://confluence.atlassian.com/confkb/confluence-does-not-start-due-to-there-may-be-a-configuration-problem-in-your-confluence-cfg-xml-file-241568568.html
# rm -rf ${CONFLUENCE_HOME}/*

# Start Confluence as the correct user
if [ "${UID}" -eq 0 ]; then
    echo "User is currently root. Will change directory ownership to ${RUN_USER}:${RUN_GROUP}, then downgrade permission to ${RUN_USER}"
    PERMISSIONS_SIGNATURE=$(stat -c "%u:%U:%a" "${CONFLUENCE_HOME}")
    EXPECTED_PERMISSIONS=$(id -u ${RUN_USER}):${RUN_GROUP}:775
    if [ "${PERMISSIONS_SIGNATURE}" != "${EXPECTED_PERMISSIONS}" ]; then
        chmod -R 775 "${CONFLUENCE_HOME}" &&
        chown -R "${RUN_USER}:${RUN_GROUP}" "${CONFLUENCE_HOME}"
    fi
    # Now drop privileges
    exec su -s /bin/bash "${RUN_USER}" -c "$CONFLUENCE_INSTALL_DIR/bin/start-confluence.sh $@"
else
    echo "User is not root"
    echo "User is ${RUN_USER}"
    echo "umask is: "$(umask)
    exec "$CONFLUENCE_INSTALL_DIR/bin/start-confluence.sh" "$@"
fi

