###########################################################################################
FROM golang:alpine AS shfmt

LABEL name="shfmt"
LABEL version="2.5.1"

ENV GOOS linux
ENV CGO_ENABLED 0
ENV SHFMT_VERSION 2.5.1

RUN apk add --no-cache git \
      && go get -u mvdan.cc/sh/cmd/shfmt \
      && git -C "$GOPATH/src/mvdan.cc/sh" checkout -q "v$SHFMT_VERSION" \
      && go install -a -ldflags '-extldflags "-static"' mvdan.cc/sh/cmd/shfmt

###########################################################################################
# Get maintainers container so we can copy non-linked binary in to ours
FROM koalaman/shellcheck AS shellcheck
###########################################################################################
FROM docker/compose:1.22.0 AS docker-compose
###########################################################################################
FROM bats/bats:v1.1 as bats
###########################################################################################
FROM alpine/helm:2.11.0 as helm
###########################################################################################
FROM docker.bintray.io/jfrog/jfrog-cli-go:1.22.0 as jfrog
###########################################################################################
# Copy docker/docker-compose
COPY --from=docker-compose /usr/local/bin/docker ${HOME}/.local/bin/
COPY --from=docker-compose /usr/local/bin/docker-compose ${HOME}/.local/bin/

###########################################################################################
FROM python:3.7-alpine as stage_collector

RUN mkdir /tmp/bin
COPY bin/ /tmp/bin/
COPY --from=shfmt /go/bin/shfmt /tmp/bin/
COPY --from=shellcheck /bin/shellcheck /tmp/bin/
COPY --from=docker-compose /usr/local/bin/docker /tmp/bin/
COPY --from=docker-compose /usr/local/bin/docker-compose /tmp/bin/
COPY --from=helm /usr/bin/helm /tmp/bin/
COPY --from=jfrog /usr/local/bin/jfrog /tmp/bin/
###
# Install minikube
ENV MINIKUBE_VERSION 0.32.0
RUN apk add --no-cache curl \
    && curl -Lo /tmp/bin/minikube https://github.com/kubernetes/minikube/releases/download/v0.32.0/minikube-linux-amd64 \
    && chmod ugo+x /tmp/bin/minikube
###
RUN mkdir /tmp/home
COPY config/bootstrap /tmp/home/
###########################################################################################

# Resulting image
FROM python:3.7-alpine
ENV HOME=/home/dlt \
    GLIBC=2.28-r0

# Required for docker-compose
RUN apk update && apk add --no-cache openssl ca-certificates curl libgcc && \
    curl -fsSL -o /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    curl -fsSL -o glibc-${GLIBC}.apk https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GLIBC/glibc-$GLIBC.apk && \
    apk add --no-cache glibc-$GLIBC.apk && \
    ln -s /lib/libz.so.1 /usr/glibc-compat/lib/ && \
    ln -s /lib/libc.musl-x86_64.so.1 /usr/glibc-compat/lib && \
    ln -s /usr/lib/libgcc_s.so.1 /usr/glibc-compat/lib && \
    rm /etc/apk/keys/sgerrand.rsa.pub glibc-$GLIBC.apk

# Copy things
#COPY config/requirements.txt /

# Base components
ENV FIXUID_VERSION="0.4" \
    FIXUID_SHA256="e901f3b21e62ebed92172df969bfc6cbfdfa8f53afb060f20f25e77dcbc20ff5"
RUN apk add --no-cache \
      bash \
      curl \
      git \
      jq \
      make \
      shadow \
      sudo \
    && curl -L -o /tmp/grpcurl.tar.gz https://github.com/fullstorydev/grpcurl/releases/download/v1.0.0/grpcurl_1.0.0_linux_x86_64.tar.gz \
    && mkdir /tmp/grpcurl \
    && tar -zxvf /tmp/grpcurl.tar.gz -C /tmp/grpcurl/ \
    && mv /tmp/grpcurl/grpcurl /usr/local/bin \
    && ln -s /opt/bats/bin/bats /usr/local/bin/bats \
    && curl -SsL "https://github.com/boxboat/fixuid/releases/download/v${FIXUID_VERSION}/fixuid-${FIXUID_VERSION}-linux-amd64.tar.gz" | tar -C /usr/local/bin -xzf - \
    && echo "${FIXUID_SHA256}  /usr/local/bin/fixuid" | sha256sum -c \
    && chown root:root /usr/local/bin/fixuid \
    && chmod 4755 /usr/local/bin/fixuid \
    && mkdir -p /etc/fixuid

# Userland part
RUN addgroup -g 1000 dlt \
    && adduser -u 1000 -G dlt -h ${HOME} -s /bin/bash -D dlt \
    && echo "dlt ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && echo -e "user: dlt\ngroup: dlt\n" > /etc/fixuid/config.yml
USER dlt
RUN mkdir ${HOME}/workspace

# copy over assets
COPY --chown=dlt:dlt --from=bats /opt/bats /opt/bats
COPY --chown=dlt:dlt --from=stage_collector /tmp/bin/ /usr/local/bin/
COPY --chown=dlt:dlt --from=stage_collector /tmp/home/ ${HOME}/

# entrypoint
COPY --chown=dlt:dlt config/entrypoint.sh /
ENTRYPOINT [ "/entrypoint.sh" ]
WORKDIR ${HOME}/workspace

