# syntax=docker/dockerfile:1
#
# Servoy test-e2e environment
#
# Build (from repo root):
#   docker build -f build/docker/test-e2e/Dockerfile -t servoy-test-e2e .
#
# Run:
#   docker run --rm \
#     -e PROJECT_NAME=MyServoyApp \
#     servoy-test-e2e

FROM debian:bookworm-slim
ARG NODE_VERSION=22.16.0

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

ARG TOMCAT_VERSION=9.0.117
ENV CATALINA_HOME=/opt/tomcat

RUN set -eux; \
    wget -q "https://downloads.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz" \
         -O /tmp/tomcat.tar.gz; \
    mkdir -p "${CATALINA_HOME}"; \
    tar -xzf /tmp/tomcat.tar.gz -C "${CATALINA_HOME}" --strip-components=1; \
    rm /tmp/tomcat.tar.gz; \
    rm -rf "${CATALINA_HOME}/webapps/ROOT" "${CATALINA_HOME}/webapps/ROOT.war"; \
    chmod +x "${CATALINA_HOME}/bin"/*.sh

COPY build/tomcat/setenv.sh "${CATALINA_HOME}/bin/setenv.sh"
RUN sed -i 's/\r$//' "${CATALINA_HOME}/bin/setenv.sh" && chmod +x "${CATALINA_HOME}/bin/setenv.sh"

ENV PATH="${CATALINA_HOME}/bin:${PATH}"
ENV SERVOY_HOME=/opt/servoy
ENV SERVOY_USER_HOME=/var/servoy-home
ENV SOURCE_DIR=/workspace/src
ENV PRISMA_WORKDIR=/workspace
ENV ENABLE_LOCAL_MYSQL=true
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

COPY artifacts/servoy_linux.4046.tar.gz /tmp/servoy.tar.gz
RUN set -eux; \
    mkdir -p "${SERVOY_HOME}"; \
    tar -xzf /tmp/servoy.tar.gz -C "${SERVOY_HOME}"; \
    rm /tmp/servoy.tar.gz; \
    find "${SERVOY_HOME}" -name "*.sh" -exec chmod +x {} \;; \
    mkdir -p "${SERVOY_USER_HOME}"; \
    chmod 0777 "${SERVOY_USER_HOME}"

COPY src "${SOURCE_DIR}"
COPY package.json package-lock.json prisma.appdb.config.ts "${PRISMA_WORKDIR}/"
COPY prisma "${PRISMA_WORKDIR}/prisma"

RUN set -eux; \
    cd "${PRISMA_WORKDIR}"; \
    npm ci

# Environment-specific Servoy WAR-export config template.
COPY build/docker/test-e2e/servoy.properties /config/servoy.properties

RUN set -eux; \
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 | gpg --dearmor > /usr/share/keyrings/mysql-archive-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mysql-archive-keyring.gpg] https://repo.mysql.com/apt/debian bookworm mysql-8.4-lts" > /etc/apt/sources.list.d/mysql.list; \
    apt-get update; \
    echo "mysql-community-server mysql-community-server/root-pass password ''" | debconf-set-selections; \
    echo "mysql-community-server mysql-community-server/re-root-pass password ''" | debconf-set-selections; \
    echo 'exit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-community-server; \
    rm /usr/sbin/policy-rc.d; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /var/lib/mysql/*; \
    mkdir -p /var/lib/mysql && chown -R mysql:mysql /var/lib/mysql; \
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

COPY build/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 8080 3306

ENTRYPOINT ["/entrypoint.sh"]
