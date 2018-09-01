# Dockerfile based on https://hub.docker.com/r/atlassian/confluence-server/~/dockerfile/
FROM anapsix/alpine-java:8_jdk
MAINTAINER Atlassian Confluence

ENV RUN_USER           1001
ENV RUN_GROUP          root

ENV UID ${RUN_USER}

#ENV http_proxy http://user:passwordproxy.com:80
#ENV https_proxy http://user:password@proxy.com:80

# https://confluence.atlassian.com/doc/confluence-home-and-other-important-directories-590259707.html
ENV CONFLUENCE_HOME          /var/atlassian/application-data/confluence
ENV CONFLUENCE_INSTALL_DIR   /opt/atlassian/confluence

VOLUME ["${CONFLUENCE_HOME}"]

# Expose HTTP and Synchrony ports
EXPOSE 8090
EXPOSE 8091

WORKDIR $CONFLUENCE_HOME

#CMD ["sh", "/entrypoint.sh", "-fg"]
CMD ["/entrypoint.sh", "-fg"]
ENTRYPOINT ["/sbin/tini", "--"]

RUN apk update -qq \
    && apk add ca-certificates wget curl openssh bash procps openssl perl ttf-dejavu tini \
    && update-ca-certificates \
    && rm -rf /var/lib/{apt,dpkg,cache,log}/ /tmp/* /var/tmp/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod 777 /entrypoint.sh

ARG CONFLUENCE_VERSION=6.10.1
ARG DOWNLOAD_URL=http://www.atlassian.com/software/confluence/downloads/binary/atlassian-confluence-${CONFLUENCE_VERSION}.tar.gz

COPY . /tmp

RUN mkdir -p                             ${CONFLUENCE_INSTALL_DIR} \
    && curl -L --silent                  ${DOWNLOAD_URL} | tar -xz --strip-components=1 -C "$CONFLUENCE_INSTALL_DIR" \
    && chown -R ${RUN_USER}:${RUN_GROUP} ${CONFLUENCE_INSTALL_DIR}/ \
    && sed -i -e 's/-Xms\([0-9]\+[kmg]\) -Xmx\([0-9]\+[kmg]\)/-Xms\${JVM_MINIMUM_MEMORY:=\1} -Xmx\${JVM_MAXIMUM_MEMORY:=\2} \${JVM_SUPPORT_RECOMMENDED_ARGS} -Dconfluence.home=\${CONFLUENCE_HOME}/g' ${CONFLUENCE_INSTALL_DIR}/bin/setenv.sh \
    && sed -i -e 's/port="8090"/port="8090" secure="${catalinaConnectorSecure}" scheme="${catalinaConnectorScheme}" proxyName="${catalinaConnectorProxyName}" proxyPort="${catalinaConnectorProxyPort}"/' ${CONFLUENCE_INSTALL_DIR}/conf/server.xml

# Updating postgres drivers:
#ADD https://jdbc.postgresql.org/download/postgresql-42.2.4.jar /opt/atlassian/confluence/confluence/WEB-INF/lib
#RUN chmod +x /opt/atlassian/confluence/confluence/WEB-INF/lib/postgresql-42.2.4.jar
#RUN rm /opt/atlassian/confluence/confluence/WEB-INF/lib/postgresql-42.1.1.jar

# Support Arbitrary User IDs (Reference: OpenShift Container Platform 3.9 Image Creation Guide):
#RUN chown -R ${RUN_USER}:${RUN_GROUP} ${CONFLUENCE_HOME}
#RUN chgrp -R 0 ${CONFLUENCE_INSTALL_DIR}
RUN umask 0002 \
    && chgrp -R 0 ${CONFLUENCE_INSTALL_DIR} \
    && chmod -R g=u ${CONFLUENCE_INSTALL_DIR} \
    && chgrp -R 0 ${CONFLUENCE_HOME} \
    && chmod -R g=u ${CONFLUENCE_HOME} \
    #&& chmod -R 775 ${CONFLUENCE_HOME} \
    #&& chmod g-s ${CONFLUENCE_HOME} \
    && chmod g=u /etc/passwd \
    && chmod g=u /etc/group 
    #&& chmod g=u /etc/profile 
#RUN chmod -R 775 ${CONFLUENCE_INSTALL_DIR} 
#RUN chmod -R 775 ${CONFLUENCE_HOME}
#RUN chmod g-s ${CONFLUENCE_HOME}

#RUN chmod g=u /etc/passwd
#RUN chmod g=u /etc/group
#RUN chmod g=u /etc/profile
USER 1001  
# End of Support Arbitrary User IDs
