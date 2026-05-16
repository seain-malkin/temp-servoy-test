#!/bin/sh
# entrypoint.sh — start MySQL → clone → build WAR → deploy → start Tomcat → health check → exit
#
# Required environment variables:
#   REPO_URL      Git URL of the Servoy project (e.g. https://github.com/org/repo)
#   PROJECT_NAME  Servoy application/project name to export as a WAR
#
# Optional environment variables:
#   REPO_BRANCH          Branch to clone (default: main)
#   GITHUB_TOKEN         Personal access token for private repos
#   HEALTH_CHECK_URL     URL to poll after Tomcat starts (default: http://localhost:8080/)
#   HEALTH_CHECK_RETRIES Number of times to retry the health check (default: 30)
#   HEALTH_CHECK_DELAY   Seconds between retries (default: 5)
#   WAR_EXTRA_ARGS       Additional arguments to pass to war_export.sh
#   WAR_ADMIN_USER       Default admin username for WAR export (default: admin)
#   WAR_ADMIN_PASSWORD   Default admin password for WAR export (default: admin)
#   WORKSPACE_DIR        Where to clone the repo (default: /workspace)
#   MYSQL_ROOT_PASSWORD  Root password to set after init (default: no password)
#   MYSQL_DATABASE       Database to create on startup
#   MYSQL_USER           App user to create (requires MYSQL_DATABASE)
#   MYSQL_PASSWORD       Password for MYSQL_USER

set -e

# ── Defaults ─────────────────────────────────────────────────────────────────
REPO_BRANCH="${REPO_BRANCH:-main}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:8080/}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-5}"
WAR_OUTPUT="/tmp/servoy-app.war"
WAR_OUTPUT_DIR="$(dirname "${WAR_OUTPUT}")"
WAR_FILE_BASENAME="$(basename "${WAR_OUTPUT}" .war)"
WAR_PROPERTIES_FILE="/tmp/servoy-war.properties"
WAR_EXPORTER="${SERVOY_HOME}/developer/exporter/war_export.sh"
WAR_ADMIN_USER="${WAR_ADMIN_USER:-admin}"
WAR_ADMIN_PASSWORD="${WAR_ADMIN_PASSWORD:-admin}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
REPOSITORY_DB_NAME="${MYSQL_DATABASE:-repository_server}"

# Helper: run mysql as root, with or without a password
mysql_root() {
  if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$@"
  else
    mysql -u root "$@"
  fi
}

# ── Validate required vars ────────────────────────────────────────────────────
if [ -z "${REPO_URL}" ]; then
  echo "ERROR: REPO_URL is required." >&2
  exit 1
fi
if [ -z "${PROJECT_NAME}" ]; then
  echo "ERROR: PROJECT_NAME is required." >&2
  exit 1
fi

# ── Start MySQL ───────────────────────────────────────────────────────────────
if [ -d "/var/lib/mysql/mysql" ]; then
  echo "==> MySQL data directory already initialized."
else
  echo "==> Initialising MySQL data directory..."
  mysqld --initialize-insecure --user=mysql 2>&1
fi

echo "==> Starting MySQL..."
mysqld --user=mysql &

echo "==> Waiting for MySQL to be ready..."
i=0
while [ "${i}" -lt 30 ]; do
  if mysqladmin -u root ping --silent 2>/dev/null; then
    echo "==> MySQL is ready."
    break
  fi
  i=$((i + 1))
  echo "    Attempt ${i}/30 — not ready yet, waiting 2s..."
  sleep 2
done

if [ "${i}" -ge 30 ]; then
  echo "ERROR: MySQL did not become ready in time." >&2
  echo "==> MySQL error log:" >&2
  cat /var/log/mysql/error.log >&2
  exit 1
fi

if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
  echo "==> Setting MySQL root password..."
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
fi

echo "==> Creating database '${REPOSITORY_DB_NAME}'..."
mysql_root -e "CREATE DATABASE IF NOT EXISTS \`${REPOSITORY_DB_NAME}\`;"

if [ -n "${MYSQL_USER}" ] && [ -n "${MYSQL_PASSWORD}" ]; then
  echo "==> Creating MySQL user '${MYSQL_USER}'..."
  mysql_root \
    -e "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';" \
    -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE:-*}\`.* TO '${MYSQL_USER}'@'%';" \
    -e "FLUSH PRIVILEGES;"
fi

echo "==> Verifying MySQL query readiness..."
i=0
while [ "${i}" -lt 30 ]; do
  if [ -n "${MYSQL_DATABASE}" ]; then
    if mysql_root -e "USE \`${MYSQL_DATABASE}\`; SELECT 1;" >/dev/null 2>&1; then
      echo "==> MySQL is active and database '${MYSQL_DATABASE}' is queryable."
      break
    fi
  else
    if mysql_root -e "SELECT 1;" >/dev/null 2>&1; then
      echo "==> MySQL is active and queryable."
      break
    fi
  fi
  i=$((i + 1))
  echo "    Attempt ${i}/30 — query check failed, waiting 2s..."
  sleep 2
done

if [ "${i}" -ge 30 ]; then
  echo "ERROR: MySQL did not become query-ready in time." >&2
  echo "==> MySQL error log:" >&2
  cat /var/log/mysql/error.log >&2
  exit 1
fi

if [ -n "${MYSQL_USER}" ]; then
  REPOSITORY_DB_USER="${MYSQL_USER}"
  REPOSITORY_DB_PASSWORD="${MYSQL_PASSWORD:-}"
else
  REPOSITORY_DB_USER="root"
  REPOSITORY_DB_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
fi

echo "==> Generating WAR properties with repository_server mapping..."
cp "${SERVOY_HOME}/application_server/servoy.properties" "${WAR_PROPERTIES_FILE}"
cat >> "${WAR_PROPERTIES_FILE}" <<EOF

ServerManager.numberOfServers=1
repository_server=server.0
server.0.serverName=repository_server
server.0.servername=repository_server
server.0.URL=jdbc:mysql://127.0.0.1:3306/${REPOSITORY_DB_NAME}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true
server.0.userName=${REPOSITORY_DB_USER}
server.0.user=${REPOSITORY_DB_USER}
server.0.password=${REPOSITORY_DB_PASSWORD}
server.0.driver=com.mysql.cj.jdbc.Driver
server.0.catalog=${REPOSITORY_DB_NAME}
server.0.maxActive=30
server.0.validationQuery=select 1
server.0.connectionValidationType=0
EOF

echo "==> Cloning ${REPO_URL} (branch: ${REPO_BRANCH})..."

# Inject token into HTTPS URL for private repos
CLONE_URL="${REPO_URL}"
if [ -n "${GITHUB_TOKEN}" ]; then
  # Strip any existing credentials, then inject the token
  CLONE_URL=$(echo "${REPO_URL}" | sed 's|https://|https://x-access-token:'"${GITHUB_TOKEN}"'@|')
fi

rm -rf "${WORKSPACE_DIR}"
git clone --depth=1 --branch "${REPO_BRANCH}" "${CLONE_URL}" "${WORKSPACE_DIR}"
echo "==> Clone complete."

# ── Show war_export.sh usage for diagnostics ─────────────────────────────────
# echo "==> war_export.sh usage:"
# "${WAR_EXPORTER}" 2>&1 || true   # exits non-zero when called with no args — that's expected

# ── Build the WAR ─────────────────────────────────────────────────────────────
echo "==> Building WAR for project '${PROJECT_NAME}'..."
"${WAR_EXPORTER}" \
  -s "${PROJECT_NAME}" \
  -o "${WAR_OUTPUT_DIR}" \
  -data "${WORKSPACE_DIR}" \
  -warFileName "${WAR_FILE_BASENAME}" \
  -pfw "${WAR_PROPERTIES_FILE}" \
  -as "${SERVOY_HOME}/application_server" \
  -pluginLocations "${SERVOY_HOME}/developer/plugins" \
  -defaultAdminUser "${WAR_ADMIN_USER}" \
  -defaultAdminPassword "${WAR_ADMIN_PASSWORD}" \
  ${WAR_EXTRA_ARGS:-}

echo "==> WAR built: ${WAR_OUTPUT}"

# ── Deploy to Tomcat ──────────────────────────────────────────────────────────
echo "==> Deploying WAR to Tomcat..."
cp "${WAR_OUTPUT}" "${CATALINA_HOME}/webapps/ROOT.war"

# ── Start Tomcat ──────────────────────────────────────────────────────────────
echo "==> Starting Tomcat..."
"${CATALINA_HOME}/bin/catalina.sh" start

# ── Wait for Tomcat to be ready ───────────────────────────────────────────────
echo "==> Waiting for Tomcat at ${HEALTH_CHECK_URL} ..."
i=0
while [ "${i}" -lt "${HEALTH_CHECK_RETRIES}" ]; do
  if curl -sf -o /dev/null "${HEALTH_CHECK_URL}"; then
    echo "==> Tomcat is up."
    break
  fi
  i=$((i + 1))
  echo "    Attempt ${i}/${HEALTH_CHECK_RETRIES} — not ready yet, waiting ${HEALTH_CHECK_DELAY}s..."
  sleep "${HEALTH_CHECK_DELAY}"
done

if [ "${i}" -ge "${HEALTH_CHECK_RETRIES}" ]; then
  echo "ERROR: Tomcat did not become ready after $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_DELAY))s." >&2
  echo "==> Tomcat logs:" >&2
  cat "${CATALINA_HOME}/logs/catalina.out" >&2
  echo "==> MySQL error log:" >&2
  cat /var/log/mysql/error.log >&2
  exit 1
fi

# ── Health check ─────────────────────────────────────────────────────────────
echo "==> Running health check against ${HEALTH_CHECK_URL} ..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_CHECK_URL}")

if [ "${HTTP_STATUS}" -ge 200 ] && [ "${HTTP_STATUS}" -lt 400 ]; then
  echo "==> Health check passed (HTTP ${HTTP_STATUS})."
  exit 0
else
  echo "ERROR: Health check failed (HTTP ${HTTP_STATUS})." >&2
  echo "==> Tomcat logs:" >&2
  cat "${CATALINA_HOME}/logs/catalina.out" >&2
  echo "==> MySQL error log:" >&2
  cat /var/log/mysql/error.log >&2
  exit 1
fi
