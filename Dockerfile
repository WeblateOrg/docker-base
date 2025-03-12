# Copyright © Michal Čihař <michal@weblate.org>
#
# SPDX-License-Identifier: MIT

FROM python:3.13.2-slim-bookworm
ARG TARGETARCH

ENV UV_VERSION=0.6.6
ENV PYVERSION=3.13

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
  useradd --shell /bin/sh --user-group weblate --groups root,tty \
  && mkdir -p /home/weblate/.ssh \
  && touch /home/weblate/.ssh/authorized_keys \
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
ENV PATH=/app/venv/bin:/opt/tools/bin:/usr/local/bin:/usr/bin:/bin

# Debian packages pins

# renovate: repo=https://ppa.launchpadcontent.net/git-core/ppa/ubuntu release=jammy depName=git
ENV GIT_VERSION="1:2.48.1-0ppa1~ubuntu22.04.1"
# renovate: release=bookworm depName=ca-certificates
ENV CA_VERSION="20230311"
# renovate: release=bookworm depName=curl
ENV CURL_VERSION="7.88.1-10+deb12u8"
# renovate: release=bookworm depName=openssh-client
ENV OPENSSH_VERSION="1:9.2p1-2+deb12u4"
# renovate: repo=https://apt.postgresql.org/pub/repos/apt release=bookworm-pgdg depName=postgresql-client-17
ENV POSTGRESQL_VERSION="17.4-1.pgdg120+2"

# Install dependencies
# hadolint ignore=DL3008,DL3013,SC2046,DL3003
RUN \
  export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install --no-install-recommends -y \
    nginx-light \
    ruby-licensee \
    openssh-client="${OPENSSH_VERSION}" \
    ca-certificates="${CA_VERSION}" \
    curl="${CURL_VERSION}" \
    gir1.2-pango-1.0 \
    gir1.2-rsvg-2.0 \
    libxmlsec1-openssl \
    libjpeg62-turbo \
    libmariadb3 \
    gettext \
    gnupg \
    subversion \
    file \
    locales \
    libldap-common \
    libcairo-gobject2 \
    libenchant-2-2 \
    unzip \
    xz-utils \
  && c_rehash \
  && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && /usr/sbin/locale-gen \
  && install -d /etc/apt/keyrings \
  && curl -o /etc/apt/keyrings/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  && echo "deb [signed-by=/etc/apt/keyrings/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  && curl -o /etc/apt/keyrings/git-core.launchpad.net.asc --fail 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xe363c90f8f1b6217' \
  && echo "deb [signed-by=/etc/apt/keyrings/git-core.launchpad.net.asc] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu jammy main" > /etc/apt/sources.list.d/git.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y \
    postgresql-client-17="${POSTGRESQL_VERSION}" \
    git="${GIT_VERSION}" \
    git-svn \
  && apt-get clean \
  && rm -rf /root/.cache /tmp/* /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

# Install supervisor and gunicorn to /opt/tools
RUN export UV_NO_CACHE=1 && uv venv /opt/tools
COPY --link requirements.txt /opt/tools/src/requirements.txt
# hadolint ignore=SC1091
RUN export UV_NO_CACHE=1 && \
    source /opt/tools/bin/activate && \
    uv pip install -r /opt/tools/src/requirements.txt
