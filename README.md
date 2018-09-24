# Confluence 6 docker image for Openshift
# Table of Contents
<!-- TOC -->
- [Table of Contents](#table-of-contents)
- [HowTo Build a custom Confluence 6 docker image with a public dockerhub image as a base](#howto-build-a-custom-confluence-6-docker-image-with-a-public-dockerhub-image-as-a-base)
    - [Alternatives: Other Docker images for Confluence 6 on Openshift](#alternatives-other-docker-images-for-confluence-6-on-openshift)
    - [Files in this repo](#files-in-this-repo)
    - [Configuration](#configuration)
        - [Jenkins Slave Requirements](#jenkins-slave-requirements)
        - [Container Requirements](#container-requirements)
        - [Openshift Requirements](#openshift-requirements)
            - [Support Arbitrary User IDs](#support-arbitrary-user-ids)
            - [Configuring HAProxy Timeouts with Route Annotations](#configuring-haproxy-timeouts-with-route-annotations)
        - [Database drivers requirements](#database-drivers-requirements)
            - [PostgreSQL driver](#postgresql-driver)
            - [Microsoft SQL Server driver](#microsoft-sql-server-driver)
            - [MySQL driver](#mysql-driver)
            - [Oracle driver](#oracle-driver)
        - [PostgreSQL container images](#postgresql-container-images)
        - [Docker Engine running in your development environment](#docker-engine-running-in-your-development-environment)
    - [Pulling and running the container](#pulling-and-running-the-container)
    - [Running and connecting Frontend container and Backend container](#running-and-connecting-frontend-container-and-backend-container)
    - [How to Debug in our Virtualbox Development environment with Docker engine](#how-to-debug-in-our-virtualbox-development-environment-with-docker-engine)
    - [Testing connectivity from confluence6 container to postgresql container](#testing-connectivity-from-confluence6-container-to-postgresql-container)
        - [Getting IP address of PostgreSQL container](#getting-ip-address-of-postgresql-container)
        - [Testing connectivity from Confluence6 container towards PostgresSQL container](#testing-connectivity-from-confluence6-container-towards-postgressql-container)
    - [How to Debug in Openshift when a deployment fails](#how-to-debug-in-openshift-when-a-deployment-fails)
        - [Examples:](#examples)
- [Known Errors](#known-errors)
    - [Spring Application context has not been set](#spring-application-context-has-not-been-set)
    - [Installation Fails When Attempting to Install Database](#installation-fails-when-attempting-to-install-database)
    - [Confluence will not start up because the build number in the home directory does not match the build number in the database after upgrade](#confluence-will-not-start-up-because-the-build-number-in-the-home-directory-does-not-match-the-build-number-in-the-database-after-upgrade)
- [References](#references)

<!-- /TOC -->
# HowTo Build Atlassian's official Confluence 6 docker image to make it work in Openshift and with Oracle Java
* Modified Dockerfile based on the Official Confluence 6 Docker image: https://hub.docker.com/r/atlassian/confluence-server/
* Aim: 
    - Attempting to deploy Confluence 6 server using the Official Docker image within the “Openshift Container Platform”, a Kubernetes management and orchestration platform for Docker containers. 
    - **Atlassian do not directly support Openshift.** 
    - Atlassian support their own Docker container edition, however unless you are evaluating Confluence your image needs to be running using the Oracle JDK to meet the supported platform requirements, you’ll need to build your own image by following the [Update the Confluence Docker image to use Oracle JDK](https://confluence.atlassian.com/confkb/update-the-confluence-docker-image-to-use-oracle-jdk-829062521.html) steps here. 
* This image has been developed and tested in the following environment:
    * **Openshift.com account** with 6GiB of RAM + 4GiB of persistent storage + 2Gib of Terminating Memory. 
    * **quay.io** private Container Registry (where I build this Dockerfile). Openshift Secrets need to be setup to pull the Confluence6 image from this private registry:
         - Resources -> Secrets -> Create Secret:
            - Secret Type: Image Secret
            - Secret Name: <my_quay.io>
            - Authentication Type: Image Registry Credentials
            - Image Registry Server Address: **quay.io**  (docker.io if you work with hub.docker.com container registry)
            - Username: <my_username>
            - Password: <my_password>
            - Email: <my_email@addr.com>
            - Link secret to a service account: **default**
                - Check this has been added to "imagePullSecrets" in: Resources -> Other Resources -> Service Account -> default -> Actions -> Edit YAML
        - Deploy Image:
            - Add to Project -> Deploy image -> click on "Image Name":
                - quay.io: quay.io/<my_username>/<my_container_image_repository>
                - hub.docker.com: docker.io/<my_username>/<my_container_image_repository>
        - Edit Deployment Config: 
            - Image Name: quay.io/<my_username>/<my_container_image_repository>:latest
            - Advanced Image Options -> Pull Secret: <my_quay.io>
* **confluence6-docker-build.Jenkinsfile**: Alternatively, this image can be built in a custom Jenkins Slave with docker + oc tools installed. (**Not built inside OpenShift**, you won't see **confluence6-atlassian-xx-build** in the ouput of **oc get pods**). The built image can be pushed to a private repo in Dockerhub or to Openshift Registry (Development or Production). This is achieved via a Conditional Build Step in Jenkinsfile **(stages are disabled)**. 
* **Docker Desktop Environment:** If you don't have admin rights in your laptop to install Docker for Windows, ask your company to install Virtualbox instead. A Desktop Test Environment can be a Virtual Machine with at least 4GB of RAM running in your laptop with Virtualbox:
    * Virtual Machine Option 1 - Docker Toolbox: https://docs.docker.com/toolbox/overview/
    * Virtual Machine Option 2 - Fedora Osbox: https://www.osboxes.org/fedora/
    * etc.

## Alternatives: Other Docker images for Confluence 6 on Openshift 
- https://github.com/mwaeckerlin/confluence : The Confluence docker image provided by Atlassian does not run on OpenShift due to the access rights. This image does. Also it is setup in a simpler way, than the original and about 100MB smaller in size.
- https://github.com/org-binbab/openshift-confluence (Confluence 5 + MySQL connector)
- https://github.com/opendevstack/ods-core : contains the core of open dev stack - infrastructure setup based on atlassian tooling, jenkins, nexus, sonarqube and shared images.
- etc

## Files in this repo
* confluence6-docker-build.Jenkinsfile: Declarative Jenkinsfile for building and uploading the image to Openshift-DEV, Dockerhub and Openshift-PROD (**Stages are disabled via Conditional Build Steps**). Tip: A Docker Plugin for Jenkins can easily replace this Jenkinsfile.
* Dockerfile
* entrypoint.sh
* jmxContext.xml : When enabled JMX is disabled (currently not used)

## Configuration
### Jenkins Slave Requirements
- OC tools + docker installed

### Container Requirements
- Make sure the container also has enough memory to run. Atlassian recommend 2GiB of memory allocated to accommodate the application server.

### Openshift Requirements
#### Support Arbitrary User IDs
- Run confluence with arbitrary ID (see **Support Arbitrary User IDs** reference):
    - When a container is run with an external volume on Openshift, the application process doesn't run as root
user (it is different with docker) which cause the problem: application process has no permission to create file in the volumeMounts.
    - Solution for Openshift's **Arbitrary User IDs**: For an image to support running as an arbitrary user, directories and files that may be written to by processes in the image should be owned by the root group and be read/writable by that group. Files to be executed should also have group execute permissions.
    - Confluence process needs to be run within the container with a non-root User ID that belongs to a root group (required to have write access to Confluence Home).
    - $CONFLUENCE_HOME within the container needs to be setup with g+rwx permissions (root group) and with u+rwx permissions (non root user, the same uid that runs confluence process).
    - The final USER declaration in the Dockerfile should specify the user ID (numeric value) and not the user name. This allows OpenShift Container Platform to validate the authority the image is attempting to run with and prevent running images that are trying to run as root, because running containers as a privileged user exposes potential security holes. If the image does not specify a USER, it inherits the USER from the parent image. (Note: "USER" declaration is finally not needed in this Dockerfile)

#### Configuring HAProxy Timeouts with Route Annotations
- Each POD has a reverse proxy default timeout that needs to be increased if we want to avoid the problem described below.
- **Problem:** Using a Docker instance of Confluence, Installation Fails When Attempting to Install Database:
https://community.atlassian.com/t5/Confluence-questions/Using-a-Docker-instance-of-Confluence-Installation-Fails-When/qaq-p/731543
    - "The important point is to wait for another approx. 5 minutes before you reload or try to access the base url. If you reload or access the base url before, confluence would break down with the mentioned errors (Java Beans). But if you wait 5 minutes and reload after that you can proceed with the configuration. The problem seems to be that the configuration of the database continues in the background on the container, but is interrupted if confluence receives another http request."
    - "The solution proposed above was only a shortterm fix. A proper solution consists in changing the configuration of the reverse proxy. You have to increase the time limit the reverse proxy uses before it terminates an open session to something like 5 minutes instead of one minute."
```
oc describe route confluence6-atlassian
Name:                   confluence6-atlassian
Namespace:              confluence
Created:                12 minutes ago
Labels:                 app=confluence6-atlassian
Annotations:            openshift.io/host.generated=true
Requested Host:         confluence6-atlassian-confluence.e4ff.pro-eu-west-1.openshiftapps.com
                          exposed on router router (host elb.e4ff.pro-eu-west-1.openshiftapps.com) 12 minutes ago
Path:                   <none>
TLS Termination:        <none>
Insecure Policy:        <none>
Endpoint Port:          8090-tcp

Service:        confluence6-atlassian
Weight:         100 (100%)
Endpoints:      10.128.3.40:8090, 10.128.3.40:8091
```
```
oc get all | grep routes
```
``` 
oc annotate route confluence6-atlassian --overwrite haproxy.router.openshift.io/timeout=300s
```

### Database drivers requirements
#### PostgreSQL driver
- Already included in Confluence.
#### Microsoft SQL Server driver
- Already included in Confluence.
- https://developers.redhat.com/blog/2018/01/25/microsoft-sql-server-pod-openshift/
- https://hub.docker.com/r/microsoft/mssql-server-linux/

#### MySQL driver
Confluence needs a driver to connect to MySQL. You'll need to:
- Download the MySQL driver
- Drop the .jar file in /opt/atlassian/confluence/confluence/WEB-INF/lib
- Restart Confluence and continue the setup process.

#### Oracle driver
Confluence needs a driver to connect to Oracle. You'll need to:
- Download the Oracle driver
- Drop the .jar file in /opt/atlassian/confluence/confluence/WEB-INF/lib
- Restart Confluence and continue the setup process.

### PostgreSQL container images  
- **docker pull rhscl/postgresql-95-rhel7** 
    - PostgreSQL 9.5 SQL database server
    - Container Image Based on Red Hat Software Collections 2.2
- Official Postgres docker image: https://hub.docker.com/_/postgres/
- https://hub.docker.com/r/centos/postgresql-95-centos7/
- https://hub.docker.com/r/centos/postgresql-96-centos7/
- **Postgres available in Openshift Catalog:** 
    - https://github.com/sclorg/postgresql-container/
    - PostgreSQL container images based on Red Hat Software Collections and intended for OpenShift and general usage. Users can choose between Red Hat Enterprise Linux, Fedora, and CentOS based images. http://softwarecollections.org

### Docker Engine running in your development environment
- Requirement: $CONFLUENCE_HOME within the container needs to be setup with g+rwx permissions. 
- $CONFLUENCE_HOME is a volume in the confluence image, so its permissions could come from the host (outside the container).
- **Notice: When mouting a directory from the host into the container, ensure that the mounted directory has the appropriate permissions and that the owner and group of the directory matches the user UID or name which is running inside the container.**
- Solution: Make sure the host directory (filesystem/volume with confluence persistent data in the docker engine) is setup with the following permissions: 
```
chmod 775 /var/confluence6
```
These permissions will also be applied inside the container in the corresponding mapped filesystem (/var/atlassian/application-data/confluence)

## Pulling and running the container

```
docker login  
docker stop confluence6
docker rm confluence6
docker pull <username>/confluence6
docker run -v /var/confluence6:/var/atlassian/application-data/confluence --name="confluence6" -d -p 8090:8090 -p 8091:8091 cd/confluence6
```
## Running and connecting Frontend container and Backend container 
We need to connect Confluence and Postgresql containers running the same default "bridge" network (--net=bridge):
```
systemctl restart docker

docker stop confluence6
docker rm confluence6
docker pull <username>/confluence6
docker run -v /var/confluence6:/var/atlassian/application-data/confluence --name="confluence6" -d -e 'JVM_MINIMUM_MEMORY=2048m' -e 'JVM_MAXIMUM_MEMORY=2048m' -p 8090:8090 -p 8091:8091 --net=bridge cd/confluence6

docker stop postgres
docker rm postgres
docker pull centos/postgresql-96-centos7  
docker run -v /var/postgres:/var/lib/postgresql/data --name postgres -d -e 'POSTGRESQL_USER=confluence' -e 'POSTGRESQL_PASSWORD=confluence' -e 'POSTGRESQL_DATABASE=confluence' -p 5432:5432 --net=bridge centos/postgresql-96-centos7
```
## How to Debug in our Virtualbox Development environment with Docker engine
**Note:** The author of this README lacks of admin permissions to install Docker in his Windows laptop. On the other hand Virtualbox is already provided by his Company. The following command also apply in Docker for Windows.
```
docker ps -a
docker logs <container_name>
docker exec -it <container_name> bash
```

## Testing connectivity from confluence6 container to postgresql container
Linux networking tools like "ifconfig" or "ip address show" (iptools) are not available in some containers like this one with postgres. Instead docker tools are used from Docker host:

### Getting IP address of PostgreSQL container
```
docker network ls
docker inspect postgres | grep IPAddress
```
### Testing connectivity from Confluence6 container towards PostgresSQL container
Telnet and ping are not available in most containers:
```  
docker exec -it confluence6 bash
cat < /dev/tcp/<postgres_ip>/5432
```

## How to Debug in Openshift when a deployment fails
### Examples:
```
oc get pods -n <openshift-namespace> | grep ^confluence6
oc get pods -n <openshift-namespace> | grep ^postgresq
oc describe pod <pod-id> 
oc describe pod confluence6-atlassian-39-deploy
oc describe pod/confluence6-atlassian-40-s1s90
oc logs pod <pod-id>
oc logs pod/<pod-id>
oc logs pod/confluence6-atlassian-13-868wb -n <openshift-namespace>
oc logs pod/confluence6-atlassian-39-deploy -n <openshift-namespace>
oc get is -n <openshift-namespace>
oc get is  (Verify that the image stream was created)
oc delete po,dc,rc,svc,route -n <openshift-namespace> <myapp>
```

```
oc get pods -n <openshift-namespace> | grep confluence6
```

```
confluence6-atlassian-13-868wb             0/1       ImagePullBackOff   0          4d
```

Force delete POD:

```
user@host:~> oc delete pod confluence6-atlassian-13-868wb --force=true --grace-period=0
warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "confluence6-atlassian-13-868wb" deleted
```

```
confluence6-atlassian-13-swbff             0/1       ErrImagePull   0          1m
```

```
user@host:~> oc delete pod confluence6-atlassian-13-swbff --force=true --grace-period=0
warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "confluence6-atlassian-13-swbff" deleted
```

Openshift not able to pull the image from internal exposed registry:

```
use@host:~> oc logs pod/confluence6-atlassian-40-tj03j -n <openshift-namespace>
Error from server (BadRequest): container "confluence6-atlassian" in pod "confluence6-atlassian-40-tj03j" is waiting to start: image can't be pulled
```

# Known Errors
## Spring Application context has not been set
This error is commonly seen when the user running Confluence is lacking permissions in the <confluence_home> directory or during a restart of a previous failed installation. The following link goes through all of those possibilities and provides resolution steps for for each of them: https://confluence.atlassian.com/confkb/confluence-does-not-start-due-to-spring-application-context-has-not-been-set-218278311.html
## Installation Fails When Attempting to Install Database
- See [Configuring HAProxy Timeouts with Route Annotations](#configuring-haproxy-timeouts-with-route-annotations).
- https://community.atlassian.com/t5/Confluence-questions/Using-a-Docker-instance-of-Confluence-Installation-Fails-When/qaq-p/731543
## Confluence will not start up because the build number in the home directory does not match the build number in the database after upgrade
- Scope: Confluence 6 container is connected via JDBC URL to an external PostgreSQL database containing data of Confluence 5.x (modifying the file $CONFLUENCE_HOME/confluence.cfg.xml saved in a Persistent Volume Claim). This is the procedure to follow when upgrading the database schema during a Confluence migration from release 5.x to release 6.x.
- Error:
    - Confluence had problems starting up: This page is for Confluence administrators. If you're seeing this page, your Confluence administrator is probably working to restore the service.
    - Confluence will not start up because the build number in the home directory [7801] doesn't match the build number in the database [6223]
    - This installation of Confluence has failed one or more bootstrap configuration checks. Please check the logs for details.
- Solution: https://confluence.atlassian.com/confkb/confluence-will-not-start-up-because-the-build-number-in-the-home-directory-doesn-t-match-the-build-number-in-the-database-after-upgrade-376834096.html

# References
* [Docker Pipeline Plugin](https://wiki.jenkins.io/display/JENKINS/Docker+Pipeline+Plugin): Allows to build and use Docker containers from pipelines.
    * [plugins.jenkins.io: Docker Pipeline plugin](https://plugins.jenkins.io/docker-workflow)
    * [github.com: Docker Workflow Plugin](https://github.com/jenkinsci/docker-workflow-plugin)
* [jenkins.io: Building docker images with Jenkins Declarative Pipeline](https://jenkins.io/doc/book/pipeline/syntax/#agent)
* [jenkins.io: **User Docker with Pipeline. Using a custom registry**](https://jenkins.io/doc/book/pipeline/docker/)
* [jenkins.io: **Converting conditional to pipeline**](https://jenkins.io/blog/2017/01/19/converting-conditional-to-pipeline/)
* [Dzone.com: Declarative Pipeline Refcard](https://dzone.com/refcardz/declarative-pipeline-with-jenkins)
* [Cloudbees: Declarative Pipeline Quick Reference](https://www.cloudbees.com/sites/default/files/declarative-pipeline-refcard.pdf)
* [Dzone.com: Continuous Delivery with Jenkins workflow](https://dzone.com/refcardz/continuous-delivery-with-jenkins-workflow)
* [Reddit.com: jenkinsci](https://www.reddit.com/r/jenkinsci/)
* [Stackoverflow.com: Cannot download Docker images behind a proxy](https://stackoverflow.com/questions/23111631/cannot-download-docker-images-behind-a-proxy)
* [blog.openshift.com: Getting Started With Docker Registry](https://blog.openshift.com/getting-started-docker-registry/)
* [docs.docker.com: HTTP/HTTPS proxy with docker](https://docs.docker.com/config/daemon/systemd/#runtime-directory-and-storage-driver)
* [docker.com: How do I enable 'debug' logging of the Docker daemon?](https://success.docker.com/article/how-do-i-enable-debug-logging-of-the-docker-daemon)
* [docs.docker.com: Log in to a Docker registry](https://docs.docker.com/engine/reference/commandline/login/)
* [serverfault.com: How can I debug a docker container initialization?](https://serverfault.com/questions/596994/how-can-i-debug-a-docker-container-initialization)
* [Stackoverflow.com: Docker - Network calls fail during image build on corporate network](https://stackoverflow.com/questions/24151129/docker-network-calls-fail-during-image-build-on-corporate-network/)
* [docs.docker.com: docker build](https://docs.docker.com/edge/engine/reference/commandline/build/)
* [alpinelinux.org mirrors](http://dl-cdn.alpinelinux.org/alpine/MIRRORS.txt)
* [cloudbees.com: Declarative pipeline refcard](https://www.cloudbees.com/sites/default/files/declarative-pipeline-refcard.pdf)
* [docs.openshift.com: **Creating Images in Openshift. Support Arbitrary User IDs**](https://docs.openshift.com/container-platform/3.9/creating_images/guidelines.html)
* [OKD - docs.okd.io: **Creating images in Openshift. Support Arbitrary User IDs**](https://docs.okd.io/latest/creating_images/guidelines.html)
* [**OKD.io: The Origin Community Distribution of Kubernetes that powers Red Hat OpenShift** 🌟](https://www.okd.io/)
* [okd.io: **Download oc Client Tools** 🌟](https://www.okd.io/download.html)
* [blog.openshift.com: Deploying Applications from Images in OpenShift, Part One: Web Console](https://blog.openshift.com/deploying-applications-from-images-in-openshift-part-one-web-console/)
* [blog.openshift.com: Getting any Docker image running in your own OpenShift cluster](https://blog.openshift.com/getting-any-docker-image-running-in-your-own-openshift-cluster/)
* [blog.openshift.com: Deploying Images from Docker Hub](https://blog.openshift.com/deploying-images-from-dockerhub/)
* [docs.docker.com: Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
* [stackoverflow.com: How can I keep container running on Kubernetes?](https://stackoverflow.com/questions/31870222/how-can-i-keep-container-running-on-kubernetes)
* [docs.openshift.com: POD security context](https://docs.openshift.com/container-platform/3.4/install_config/persistent_storage/pod_security_context.html)
* [kubernetes.io: **How to Debug Services in Openshift Kubernetes**](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-service/)
* [blog.openshift.com: **Openshift Debugging**](https://blog.openshift.com/openshift-debugging-101/)
* [docs.openshift.com: Openshift Routes](https://docs.openshift.com/container-platform/3.9/dev_guide/routes.html)
* [Atlassian.com: **Confluence Database Configuration** 🌟](https://confluence.atlassian.com/display/DOC/Database+Configuration)
* [Atlassian.com: **Confluence 6 Supported Platforms** 🌟](https://confluence.atlassian.com/doc/supported-platforms-207488198.html)
* [Atlassian.com: Confluence 6 System Requirements](https://confluence.atlassian.com/doc/system-requirements-126517514.html)
* [Atlassian.com: **Confluence 6 database setup for postgresql** 🌟](https://confluence.atlassian.com/doc/database-setup-for-postgresql-173244522.html)
* [**forums.docker.com**](https://forums.docker.com/)
* [**Docker community Slack channel**](https://blog.docker.com/2016/11/introducing-docker-community-directory-docker-community-slack/)
* [Dzone.com Refcard: **Getting started with Docker**](https://dzone.com/refcardz/getting-started-with-docker-1)
* [Stackoverflow: How to debug "imagePullBackOff" in Openshift](https://stackoverflow.com/questions/34848422/how-to-debug-imagepullbackoff)
* [PodCTL Podcast: Containers | Kubernetes | OpenShift](https://player.fm/series/series-2285897) 
* [PodCTL Podcast: How to Deploy Applications to Kubernetes - Containers | Kubernetes | OpenShift](https://player.fm/1qzdsg) 
* [PodCTL Podcast: **Container Registries - Containers | Kubernetes | OpenShift** 🌟](https://player.fm/1saEDR) 
* [keyholesoftware.com: Managing docker containers with openshift and kubernetes](https://keyholesoftware.com/2017/12/06/managing-docker-containers-with-openshift-and-kubernetes/)
* [Dzone.com: Openshift quick start](https://dzone.com/articles/openshift-quick-start)
* [Dzone.com: Deploying images to openshift](https://dzone.com/articles/deploying-docker-images-to-openshift)
* [Dzone.com: Understanding openshift security context constrain](https://dzone.com/articles/understanding-openshift-security-context-constrain)
* [Dzone.com: A hands on with openshift 3.6](https://dzone.com/articles/a-hands-on-with-openshift-36-rc)
* [Dzone.com: A quick guide to deploying java apps on openshift](https://dzone.com/articles/a-quick-guide-to-deploying-java-apps-on-openshift)
* [Dzone.com: Troubleshooting java applications on openshift](https://dzone.com/articles/troubleshooting-java-applications-on-openshift)
* [Openshift cheat-sheet 1](https://github.com/nekop/openshift-sandbox/blob/master/docs/command-cheatsheet.md)
* [Openshift cheat-sheet 2](https://developers.redhat.com/cheat-sheets/red-hat-openshift-container-platform/)
* [**Connecting docker containers**](https://blog.csainty.com/2016/07/connecting-docker-containers.html)
* [quora.com: umask and default file permissions](https://www.quora.com/Can-we-set-file-permissions-to-775-by-using-umask-in-Linux-If-yes-what-would-the-umask-be-and-how-will-it-be-calculated)
* [confluence.atlassian.com: **Update the Confluence Docker image to use Oracle JDK** 🌟🌟](https://confluence.atlassian.com/confkb/update-the-confluence-docker-image-to-use-oracle-jdk-829062521.html)
* [confluence.atlassian.com: **Atlassian Support Offerings**](https://confluence.atlassian.com/support/atlassian-support-offerings-193299636.html)
* [**confluence.atlassian.com: Confluence does not start due to Spring Application context has not been set** 🌟](https://confluence.atlassian.com/confkb/confluence-does-not-start-due-to-spring-application-context-has-not-been-set-218278311.html)
* [**stackoverflow.com: Deploying Confluence onto Openshift**](https://stackoverflow.com/questions/14189689/deploying-atlassians-confluence-onto-openshift)
* [confluence.atlassian.com: **Atlassian Supported Platforms** 🌟](https://confluence.atlassian.com/doc/supported-platforms-207488198.html)
* [community.atlassian.com: **Using a Docker instance of Confluence, Installation Fails When Attempting to Install Database** 🌟🌟🌟](https://community.atlassian.com/t5/Confluence-questions/Using-a-Docker-instance-of-Confluence-Installation-Fails-When/qaq-p/731543)
* [stackoverflow.com: **OpenShift Service Proxy timeout**](https://stackoverflow.com/questions/47812807/openshift-service-proxy-timeout)
* [docs.openshift.com: **Configuring Route Timeouts** 🌟](https://docs.openshift.com/container-platform/3.10/install_config/configuring_routing.html)
* [docs.openshift.com: **The HAProxy Template Router** 🌟](https://docs.openshift.com/container-platform/3.10/architecture/networking/assembly_available_router_plugins.html#architecture-haproxy-router)
* [stackify.com: **The Advantages of Using Kubernetes and Docker Together** 🌟🌟🌟](https://stackify.com/kubernetes-docker-deployments/)
* [redhat.com: **How to gather and display metrics in Red Hat OpenShift** (Prometheus + Grafana)](https://www.redhat.com/en/blog/how-gather-and-display-metrics-red-hat-openshift)
* [youtube.com: **OpenShift Origin is now OKD. Installation of OKD 3.10 from start to finish** 🌟🌟🌟](https://www.youtube.com/watch?v=ZkFIozGY0IA)
* [redhat.com: How to Migrate Applications to Containers and OpenShift (Video)](https://www.redhat.com/en/about/videos/how-to-migrate-applications-to-containers-and-openshift)
* [developers.redhat.com: **Red Hat Container Development Kit** 🌟🌟🌟](https://developers.redhat.com/products/cdk/overview/)
* [udemy.com: Red Hat OpenShift With Jenkins: DevOps For Beginners 🌟🌟🌟🌟](https://www.udemy.com/red-hat-openshift)
* [udemy.com: Learn DevOps: The Complete Kubernetes Course 🌟🌟🌟🌟](https://www.udemy.com/learn-devops-the-complete-kubernetes-course)
* [udemy.com: Learn DevOps: Advanced Kubernetes Usage 🌟🌟🌟🌟](https://www.udemy.com/learn-devops-advanced-kubernetes-usage)
* [udemy.com: Understanding Confluence for users, managers and admins](https://www.udemy.com/understanding-confluence-for-users-managers-and-admins/)
* [blog.openshift.com: Introducing Red Hat Quay 🌟](https://blog.openshift.com/introducing-red-hat-quay/)
