# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: MIT

FROM ubuntu:questing-20251029@sha256:5922638447b1e3ba114332c896a2c7288c876bb94adec923d70d58a17d2fec5e
ARG TARGETARCH

# renovate: datasource=pypi depName=uv versioning=pep440
ENV UV_VERSION=0.9.15
ENV PYVERSION=3.14

LABEL name="Weblate Base"
LABEL maintainer="Michal Čihař <michal@cihar.com>"
LABEL org.opencontainers.image.url="https://weblate.org/"
LABEL org.opencontainers.image.documentation="https://docs.weblate.org/en/latest/admin/install/docker.html"
LABEL org.opencontainers.image.source="https://github.com/WeblateOrg/docker-base"
LABEL org.opencontainers.image.author="Michal Čihař <michal@weblate.org>"
LABEL org.opencontainers.image.vendor="Weblate"
LABEL org.opencontainers.image.title="Weblate Base Image"
LABEL org.opencontainers.image.description="A web-based continuous localization system with tight version control integration"
LABEL org.opencontainers.image.licenses="MIT"


SHELL ["/bin/bash", "-o", "pipefail", "-x", "-c"]

# Add user early to get a consistent userid
# - the root group so it can run with any uid
# - the tty group for /dev/std* access
# - see https://github.com/WeblateOrg/docker/issues/326 and https://github.com/moby/moby/issues/31243#issuecomment-406879017
RUN \
  userdel --remove ubuntu \
  && useradd --uid 1000 --shell /bin/sh --user-group weblate --groups root,tty \
  && mkdir -p /home/weblate/.ssh \
  && chown -R weblate:weblate /home/weblate \
  && chmod 700 /home/weblate/.ssh \
  && install -d -o weblate -g weblate -m 755 /app/data \
  && install -d -o weblate -g weblate -m 755 /app/cache

# Configure utf-8 locales to make sure Python
# correctly handles unicode filenames, configure settings
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
# Home directory
ENV HOME=/home/weblate
# Avoid Python buffering stdout and delaying logs
ENV PYTHONUNBUFFERED=1
# Add virtualenv to path
ENV PATH=/app/venv/bin:/usr/local/bin:/usr/bin:/bin

# Debian packages pins

# renovate: repo=https://ppa.launchpadcontent.net/git-core/ppa/ubuntu release=questing depName=git
ENV GIT_VERSION="1:2.52.0-0ppa1~ubuntu25.10.2"
# renovate: repo=https://archive.ubuntu.com/ubuntu release=questing depName=ca-certificates
ENV CA_VERSION="20250419"
# renovate: repo=https://archive.ubuntu.com/ubuntu release=questing depName=curl
ENV CURL_VERSION="8.14.1-2ubuntu1"
# renovate: repo=https://archive.ubuntu.com/ubuntu release=questing depName=openssh-client
ENV OPENSSH_VERSION="1:10.0p1-5ubuntu5"
# plusky-pgpg misses arm64, use noble-pgdg instead
# renovate: repo=https://apt.postgresql.org/pub/repos/apt release=noble-pgdg depName=postgresql-client-18
ENV POSTGRESQL_VERSION="18.1-1.pgdg24.04+2"

# Install dependencies
# hadolint ignore=DL3008,DL3013,SC2046,DL3003
RUN \
  export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install --no-install-recommends -y \
    nginx-light \
    openssh-client="${OPENSSH_VERSION}" \
    ca-certificates="${CA_VERSION}" \
    curl="${CURL_VERSION}" \
    gir1.2-pango-1.0 \
    gir1.2-rsvg-2.0 \
    libxml2-16 \
    libxmlsec1-openssl1 \
    libjpeg62 \
    libmariadb3 \
    gettext \
    gnupg \
    subversion \
    file \
    locales \
    libldap-common \
    libcairo-gobject2 \
    libenchant-2-2 \
    libgirepository-2.0-0 \
    supervisor \
    unzip \
    xz-utils \
  && c_rehash \
  && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && /usr/sbin/locale-gen \
  && install -d /etc/apt/keyrings \
  && curl -o /etc/apt/keyrings/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  && echo "deb [signed-by=/etc/apt/keyrings/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -o /etc/apt/keyrings/git-core.launchpad.net.asc --fail 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xe363c90f8f1b6217' \
  && echo "deb [signed-by=/etc/apt/keyrings/git-core.launchpad.net.asc] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu questing main" > /etc/apt/sources.list.d/git.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    postgresql-client-18="${POSTGRESQL_VERSION}" \
    git="${GIT_VERSION}" \
    git-svn \
  && apt-get clean \
  && rm -rf /root/.cache /tmp/* /var/lib/apt/lists/* /run/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

# Install python
RUN uv python install "${PYVERSION}"
