# syntax=docker/dockerfile:1
#
# Servoy Test Environment (legacy root Dockerfile)
#
# This file is kept for backward compatibility.
# Prefer build/docker/test-e2e/Dockerfile for new builds.
#
# Build (from repo root):
#   docker build -f build/Dockerfile -t servoy-test .
#
# Run (with external MySQL — see docker-compose.yml for local setup):
#   docker run --rm \
#     -e PROJECT_NAME=MyServoyApp \
#     -e ENABLE_LOCAL_MYSQL=false \
#     -e REPOSITORY_DB_HOST=<host> \
#     -e APP_DB_1_SERVER_NAME=appdb \
#     -e APP_DB_1_HOST=<host> \
#     -e APP_DB_1_NAME=appdb \
#     -e APP_DB_1_USER=appuser \
#     servoy-test
#
# Servoy binary prerequisite:
#   Place servoy_linux.<version>.tar.gz in artifacts/ before building.
#   In CI the tarball is downloaded automatically — see ci/README.md.

FROM debian:bookworm-slim
ARG NODE_VERSION=22.16.0

# ── System dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        curl \
        wget \
        ca-certificates \
        gnupg \
        xz-utils \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    tar -xJf "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
    rm "node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    node --version; \
    npm --version

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# ── Tomcat 9 ─────────────────────────────────────────────────────────────────
ARG TOMCAT_VERSION=9.0.117
ENV CATALINA_HOME=/opt/tomcat

RUN set -eux; \
    wget -q "https://downloads.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
         -O /tmp/tomcat.tar.gz; \
    mkdir -p "${CATALINA_HOME}"; \
    tar -xzf /tmp/tomcat.tar.gz -C "${CATALINA_HOME}" --strip-components=1; \
    rm /tmp/tomcat.tar.gz; \
    # Remove default ROOT webapp so our WAR is deployed as root
    rm -rf "${CATALINA_HOME}/webapps/ROOT" "${CATALINA_HOME}/webapps/ROOT.war"; \
    chmod +x "${CATALINA_HOME}/bin"/*.sh

COPY build/tomcat/setenv.sh "${CATALINA_HOME}/bin/setenv.sh"
RUN sed -i 's/\r$//' "${CATALINA_HOME}/bin/setenv.sh" && chmod +x "${CATALINA_HOME}/bin/setenv.sh"

ENV PATH="${CATALINA_HOME}/bin:${PATH}"
ENV SOURCE_DIR=/workspace/src
ENV PRISMA_WORKDIR=/workspace
ENV ENABLE_LOCAL_MYSQL=false
ENV DB_HOST=127.0.0.1
ENV DB_PORT=3306
ENV DB_NAME=repository_server
ENV DB_USER=root
ENV DB_PASSWORD=
ENV DB_SERVER_NAME=repository_server
ENV DB_USE_SSL=false
ENV DB_ALLOW_PUBLIC_KEY_RETRIEVAL=true
ENV DB_MAX_CONNECTIONS_ACTIVE=30
ENV DB_MAX_CONNECTIONS_IDLE=10
ENV DB_MAX_PREPARED_STATEMENTS_IDLE=100
ENV DB_CONNECTION_VALIDATION_TYPE=0
ENV DB_CLIENT_ONLY_CONNECTIONS=false
ENV DB_PREFIX_TABLES=false
ENV DB_QUERY_PROCEDURES=false
ENV DB_SCHEMA=<none>
ENV DB_SKIP_SYS_TABLES=false

# ── Servoy ───────────────────────────────────────────────────────────────────
ENV SERVOY_HOME=/opt/servoy
ENV SERVOY_USER_HOME=/var/servoy-home

# Servoy binary: place servoy_linux.*.tar.gz in artifacts/ before building.
# In CI the tarball is downloaded from the private assets repo — see ci/README.md.
COPY artifacts/ /tmp/servoy-artifacts/
RUN set -eux; \
    tarball=$(ls /tmp/servoy-artifacts/servoy_linux.*.tar.gz 2>/dev/null | head -n 1); \
    if [ -z "${tarball}" ]; then \
      echo "ERROR: No Servoy tarball found in artifacts/. Place servoy_linux.*.tar.gz there before building. See ci/README.md." >&2; \
      exit 1; \
    fi; \
    mkdir -p "${SERVOY_HOME}"; \
    tar -xzf "${tarball}" -C "${SERVOY_HOME}"; \
    rm -rf /tmp/servoy-artifacts; \
    find "${SERVOY_HOME}" -name "*.sh" -exec chmod +x {} \;

COPY src "${SOURCE_DIR}"
COPY package.json package-lock.json prisma.appdb.config.ts "${PRISMA_WORKDIR}/"
COPY prisma "${PRISMA_WORKDIR}/prisma"

RUN set -eux; \
    cd "${PRISMA_WORKDIR}"; \
    npm ci

# ── MySQL 8.4 LTS ─────────────────────────────────────────────────────────────
# NOTE: MySQL is no longer installed in this image.  Use a MySQL service container
# in CI (see .github/workflows/reusable-run-tests.yml) or docker-compose.yml locally.
# Set ENABLE_LOCAL_MYSQL=false and supply REPOSITORY_DB_* / APP_DB_1_* env vars.

# ── Entrypoint ───────────────────────────────────────────────────────────────
COPY build/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Backward-compatible default: use test-e2e env properties when building this legacy file.
COPY build/docker/test-e2e/servoy.properties /config/servoy.properties

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
