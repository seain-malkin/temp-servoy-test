# syntax=docker/dockerfile:1
#
# Servoy Test Environment
#
# Build (from repo root):
#   docker build -f docker/Dockerfile -t servoy-test .
#
# Run:
#   docker run --rm \
#     -e REPO_URL=https://github.com/org/repo \
#     -e REPO_BRANCH=main \
#     -e PROJECT_NAME=MyServoyApp \
#     [-e GITHUB_TOKEN=ghp_xxx]        # only needed for private repos
#     [-e MYSQL_ROOT_PASSWORD=secret]  # default: no root password
#     [-e MYSQL_DATABASE=mydb]         # creates DB on startup
#     [-e MYSQL_USER=appuser]          # creates app user (requires MYSQL_DATABASE)
#     [-e MYSQL_PASSWORD=apppass]      # password for MYSQL_USER
#     servoy-test

FROM debian:bookworm-slim

# ── System dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

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

COPY docker/tomcat/setenv.sh "${CATALINA_HOME}/bin/setenv.sh"
RUN sed -i 's/\r$//' "${CATALINA_HOME}/bin/setenv.sh" && chmod +x "${CATALINA_HOME}/bin/setenv.sh"

ENV PATH="${CATALINA_HOME}/bin:${PATH}"

# ── Servoy ───────────────────────────────────────────────────────────────────
ENV SERVOY_HOME=/opt/servoy

COPY artificats/servoy_linux.4046.tar.gz /tmp/servoy.tar.gz
RUN set -eux; \
    mkdir -p "${SERVOY_HOME}"; \
    tar -xzf /tmp/servoy.tar.gz -C "${SERVOY_HOME}"; \
    rm /tmp/servoy.tar.gz; \
    find "${SERVOY_HOME}" -name "*.sh" -exec chmod +x {} \;

# ── MySQL 8.4 LTS ────────────────────────────────────────────────────────────
RUN set -eux; \
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 | gpg --dearmor > /usr/share/keyrings/mysql-archive-keyring.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/mysql-archive-keyring.gpg] https://repo.mysql.com/apt/debian bookworm mysql-8.4-lts" > /etc/apt/sources.list.d/mysql.list; \
    apt-get update; \
    echo "mysql-community-server mysql-community-server/root-pass password ''" | debconf-set-selections; \
    echo "mysql-community-server mysql-community-server/re-root-pass password ''" | debconf-set-selections; \
    # Prevent the package from trying to start mysqld during install (no init system in container)
    echo 'exit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mysql-community-server; \
    rm /usr/sbin/policy-rc.d; \
    rm -rf /var/lib/apt/lists/*; \
    # Clear package-initialized data so entrypoint can do deterministic first-run init
    rm -rf /var/lib/mysql/*; \
    mkdir -p /var/lib/mysql && chown -R mysql:mysql /var/lib/mysql; \
    # Pre-create the run directory; mysqld needs it at startup
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

# ── Entrypoint ───────────────────────────────────────────────────────────────
COPY docker/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 8080 3306

ENTRYPOINT ["/entrypoint.sh"]
