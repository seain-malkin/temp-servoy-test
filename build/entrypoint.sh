#!/bin/sh
# entrypoint.sh — start MySQL (optional) → export WAR from local /workspace/src → deploy → start Tomcat → health check → exit
#
# Required environment variables:
#   PROJECT_NAME  Servoy application/project name to export as a WAR
#
# Optional environment variables:
#   SOURCE_DIR           Local Servoy workspace path inside container (default: /workspace/src)
#   HEALTH_CHECK_URL     URL to poll after Tomcat starts (default: http://localhost:8080/)
#   HEALTH_CHECK_RETRIES Number of times to retry the health check (default: 30)
#   HEALTH_CHECK_DELAY   Seconds between retries (default: 5)
#   WAR_EXTRA_ARGS       Additional arguments to pass to war_export.sh
#   WAR_ADMIN_USER       Default admin username for WAR export (default: admin)
#   WAR_ADMIN_PASSWORD   Default admin password for WAR export (default: admin)
#   WAR_PROPERTIES_TEMPLATE Path to a servoy.properties template (default: /config/servoy.properties)
#   ENABLE_LOCAL_MYSQL   Start/configure local MySQL for this container (default: true)
#   DB_HOST              Hostname for repository server DB (required when using template)
#   DB_PORT              Port for repository server DB (default: 3306)
#   DB_NAME              Database/catalog name (required when using template)
#   DB_USER              Database user (required when using template)
#   DB_PASSWORD          Database password (can be empty)
#   MYSQL_ROOT_PASSWORD  Root password to set after init (default: no password)
#   MYSQL_DATABASE       Database to create on startup
#   MYSQL_USER           App user to create (requires MYSQL_DATABASE)
#   MYSQL_PASSWORD       Password for MYSQL_USER

set -e

# ── Defaults ─────────────────────────────────────────────────────────────────
SOURCE_DIR="${SOURCE_DIR:-/workspace/src}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:8080/}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-5}"
WAR_OUTPUT="/tmp/servoy-app.war"
WAR_OUTPUT_DIR="$(dirname "${WAR_OUTPUT}")"
WAR_FILE_BASENAME="$(basename "${WAR_OUTPUT}" .war)"
WAR_PROPERTIES_FILE="/tmp/servoy.properties"
WAR_PROPERTIES_TEMPLATE="${WAR_PROPERTIES_TEMPLATE:-/config/servoy.properties}"
WAR_EXPORTER="${SERVOY_HOME}/developer/exporter/war_export.sh"
WAR_ADMIN_USER="${WAR_ADMIN_USER:-admin}"
WAR_ADMIN_PASSWORD="${WAR_ADMIN_PASSWORD:-admin}"
ENABLE_LOCAL_MYSQL="${ENABLE_LOCAL_MYSQL:-true}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_SERVER_NAME="${DB_SERVER_NAME:-repository_server}"
DB_USE_SSL="${DB_USE_SSL:-false}"
DB_ALLOW_PUBLIC_KEY_RETRIEVAL="${DB_ALLOW_PUBLIC_KEY_RETRIEVAL:-true}"
DB_MAX_CONNECTIONS_ACTIVE="${DB_MAX_CONNECTIONS_ACTIVE:-30}"
DB_MAX_CONNECTIONS_IDLE="${DB_MAX_CONNECTIONS_IDLE:-10}"
DB_MAX_PREPARED_STATEMENTS_IDLE="${DB_MAX_PREPARED_STATEMENTS_IDLE:-100}"
DB_CONNECTION_VALIDATION_TYPE="${DB_CONNECTION_VALIDATION_TYPE:-0}"
DB_CLIENT_ONLY_CONNECTIONS="${DB_CLIENT_ONLY_CONNECTIONS:-false}"
DB_PREFIX_TABLES="${DB_PREFIX_TABLES:-false}"
DB_QUERY_PROCEDURES="${DB_QUERY_PROCEDURES:-false}"
DB_SCHEMA="${DB_SCHEMA:-<none>}"
DB_SKIP_SYS_TABLES="${DB_SKIP_SYS_TABLES:-false}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

# Helper: run mysql as root, with or without a password
mysql_root() {
  if [ -n "${MYSQL_ROOT_PASSWORD}" ]; then
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$@"
  else
    mysql -u root "$@"
  fi
}

require_env() {
  var_name="$1"
  eval "var_value=\${$var_name:-}"
  if [ -z "${var_value}" ]; then
    echo "ERROR: ${var_name} is required." >&2
    exit 1
  fi
}

# ── Validate required vars ────────────────────────────────────────────────────
if [ -z "${PROJECT_NAME}" ]; then
  echo "ERROR: PROJECT_NAME is required." >&2
  exit 1
fi
if [ ! -d "${SOURCE_DIR}" ]; then
  echo "ERROR: SOURCE_DIR '${SOURCE_DIR}' does not exist." >&2
  exit 1
fi

# ── Optional local MySQL startup ──────────────────────────────────────────────
if [ "${ENABLE_LOCAL_MYSQL}" = "true" ]; then
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

  if [ -n "${MYSQL_DATABASE}" ]; then
    echo "==> Creating database '${MYSQL_DATABASE}'..."
    mysql_root -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"
  else
    echo "==> MYSQL_DATABASE not set; skipping database creation."
  fi

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
else
  echo "==> ENABLE_LOCAL_MYSQL=false, skipping local MySQL startup."
fi

echo "==> Preparing WAR properties from template..."
if [ -f "${WAR_PROPERTIES_TEMPLATE}" ]; then
  if grep -q '\${DB_' "${WAR_PROPERTIES_TEMPLATE}"; then
    require_env DB_HOST
    require_env DB_NAME
    require_env DB_USER
  fi
  envsubst '${DB_SERVER_NAME} ${DB_HOST} ${DB_PORT} ${DB_NAME} ${DB_USER} ${DB_PASSWORD} ${DB_USE_SSL} ${DB_ALLOW_PUBLIC_KEY_RETRIEVAL} ${DB_MAX_CONNECTIONS_ACTIVE} ${DB_MAX_CONNECTIONS_IDLE} ${DB_MAX_PREPARED_STATEMENTS_IDLE} ${DB_CONNECTION_VALIDATION_TYPE} ${DB_CLIENT_ONLY_CONNECTIONS} ${DB_PREFIX_TABLES} ${DB_QUERY_PROCEDURES} ${DB_SCHEMA} ${DB_SKIP_SYS_TABLES}' \
    < "${WAR_PROPERTIES_TEMPLATE}" > "${WAR_PROPERTIES_FILE}"
else
  cp "${SERVOY_HOME}/application_server/servoy.properties" "${WAR_PROPERTIES_FILE}"
fi

echo "==> Using local Servoy workspace at '${SOURCE_DIR}'."

# ── Show war_export.sh usage for diagnostics ─────────────────────────────────
# echo "==> war_export.sh usage:"
# "${WAR_EXPORTER}" 2>&1 || true   # exits non-zero when called with no args — that's expected

# ── Build the WAR ─────────────────────────────────────────────────────────────
echo "==> Building WAR for project '${PROJECT_NAME}'..."
"${WAR_EXPORTER}" \
  -s "${PROJECT_NAME}" \
  -o "${WAR_OUTPUT_DIR}" \
  -data "${SOURCE_DIR}" \
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
