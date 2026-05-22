# syntax=docker/dockerfile:1
#
# Servoy Toolchain Base Image
#
# Contains: OpenJDK 17 + Node 22 + Tomcat 9
# Does NOT contain: MySQL, Servoy binary, or application source code.
#
# This image is published to GHCR via .github/workflows/reusable-build-toolchain.yml
# and used as the base for environment-specific images (test-e2e, staging).
#
# Build locally (from repo root):
#   docker build -f ci/docker/toolchain/Dockerfile -t servoy-toolchain .

FROM debian:bookworm-slim
ARG NODE_VERSION=22.16.0
ARG TOMCAT_VERSION=9.0.117

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
