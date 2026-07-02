# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: MIT

FROM ubuntu:26.04@sha256:b7f48194d4d8b763a478a621cdc81c27be222ba2206ca3ca6bc42b49685f3d9e
ARG TARGETARCH

# renovate: datasource=github-releases depName=astral-sh/uv versioning=pep440
ENV UV_VERSION=0.11.25
ENV PYVERSION=3.14
ENV UV_PYTHON_INSTALL_DIR=/opt/python
ENV UV_CACHE_DIR=/tmp/.uv-cache

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
  && install -d -o weblate -g weblate -m 755 /opt/python \
  && install -d -o weblate -g weblate -m 755 /app/cache

# Install dependencies
# hadolint ignore=DL3008,DL3013,SC2046,DL3003
RUN \
  export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install --no-install-recommends -y \
    nginx-light \
    libnss-wrapper \
    openssh-client \
    ca-certificates \
    curl \
    gir1.2-pango-1.0 \
    gir1.2-rsvg-2.0 \
    libxml2-16 \
    libxmlsec1-openssl1 \
    libjpeg62 \
    gettext \
    gnupg \
    subversion \
    file \
    locales \
    libldap-common \
    libcairo-gobject2 \
    libgirepository-2.0-0 \
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
    postgresql-client-18 \
    git \
    git-svn \
  && apt-get clean \
  && rm -rf /root/.cache /tmp/* /var/lib/apt/lists/* /run/*

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

# Install uv
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

# Install python
RUN uv python install --no-cache "${PYVERSION}"
