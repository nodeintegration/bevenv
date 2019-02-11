#!/usr/bin/env bash

# uid checking
uid=$(id -u)

# if root, do nothing, just exec the command
[ ${uid} -eq 0 ] && exec $@

# if not 1000, fixuids
[ ${uid} -ne 1000 ] && fixuid &> /dev/null


exec_opts=''

#TODO this is a work around as we have no idea what a docker.socks permission may be
if [ -S /var/run/docker.sock ]; then
  DOCKER_SOCK_GROUP=$(stat -c '%G' /var/run/docker.sock)
  DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
  if [ "${DOCKER_SOCK_GROUP}" == 'UNKNOWN' ]; then
    sudo groupadd docker -g ${DOCKER_SOCK_GID}
    sudo usermod -G docker -a dlt
  else
    sudo usermod -G ${DOCKER_SOCK_GROUP} -a dlt
  fi
  # basically, re-login to apply new group membership when exec-ing the command
  exec_opts='sudo -Eu dlt'
fi

exec ${exec_opts} $@
