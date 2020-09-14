FROM debian:latest

## working around https://github.com/containers/libpod/issues/4605 by temporarily removing volumes
## VOLUME ["/var/cache/apt-cacher-ng"]

RUN apt update
RUN apt upgrade -y
ARG DEBIAN_FRONTEND=noninteractive
RUN apt install apt-cacher-ng -y

ADD acng.conf /etc/apt-cacher-ng/acng.conf
ADD security.conf /etc/apt-cacher-ng/security.conf
ADD centos_mirrors /etc/apt-cacher-ng/centos_mirrors

CMD chmod 777 /var/cache/apt-cacher-ng && /usr/sbin/apt-cacher-ng -c /etc/apt-cacher-ng && tail -f /var/log/apt-cacher-ng/*
