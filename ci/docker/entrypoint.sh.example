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
#   REPOSITORY_DB_HOST   Repository DB host (default: 127.0.0.1)
#   REPOSITORY_DB_PORT   Repository DB port (default: 3306)
#   REPOSITORY_DB_USER   Repository DB username (default: repository_user)
#   REPOSITORY_DB_PASSWORD Repository DB password (default: empty)
#   APP_DB_<N>_SERVER_NAME Additional application DB server alias (N=1,2,3...)
#   APP_DB_<N>_HOST        Additional application DB host
#   APP_DB_<N>_PORT        Additional application DB port (default: 3306)
#   APP_DB_<N>_NAME        Additional application DB catalog/schema
#   APP_DB_<N>_USER        Additional application DB user
#   APP_DB_<N>_PASSWORD    Additional application DB password
#   APP_DB_<N>_DATABASE_URL Optional full Prisma DATABASE_URL override for app DB N
#   ENABLE_PRISMA_MIGRATIONS Run Prisma migrations before WAR export (default: true)
#   PRISMA_APP_DB_INDEX    APP_DB index to migrate before WAR export (default: 1)
#   PRISMA_WORKDIR         Workspace containing package.json/prisma files (default: /workspace)
#   MYSQL_ROOT_PASSWORD  Root password to set after init (default: no password)
#   ENABLE_UNIT_TESTS      Run JSUnit tests before WAR export (default: false)
#   UNIT_TEST_SOLUTION     Test entry solution to export and execute (default: servoy_unit_tests)
#   UNIT_TEST_EXPORT_DIR   Folder for temporary .servoy exports used by JSUnit runner (default: /tmp/exportedSolutions)
#   UNIT_TEST_TIMEOUT_SECONDS Solution load timeout for JSUnit runner in seconds (default: 300)
#   UNIT_TEST_JAVA_OPTS    Additional JVM args for JSUnit runner invocation
#   UNIT_TEST_EXPORT_EXTRA_ARGS Additional arguments passed to export.sh before tests
#   UNIT_TEST_PROPERTIES_FILE Path to test-only Servoy properties file (default: /tmp/servoy-tests.properties)

set -e

# ── Defaults ─────────────────────────────────────────────────────────────────
SOURCE_DIR="${SOURCE_DIR:-/workspace/src}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://localhost:8080/}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-5}"
HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-5}"
WAR_OUTPUT="/tmp/servoy-app.war"
WAR_OUTPUT_DIR="$(dirname "${WAR_OUTPUT}")"
WAR_FILE_BASENAME="$(basename "${WAR_OUTPUT}" .war)"
WAR_PROPERTIES_FILE="/tmp/servoy.properties"
WAR_PROPERTIES_TEMPLATE="${WAR_PROPERTIES_TEMPLATE:-/config/servoy.properties}"
WAR_EXPORTER="${SERVOY_HOME}/developer/exporter/war_export.sh"
SOLUTION_EXPORTER="${SERVOY_HOME}/developer/exporter/export.sh"
WAR_ADMIN_USER="${WAR_ADMIN_USER:-admin}"
WAR_ADMIN_PASSWORD="${WAR_ADMIN_PASSWORD:-admin}"
ENABLE_LOCAL_MYSQL="${ENABLE_LOCAL_MYSQL:-true}"
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
ENABLE_PRISMA_MIGRATIONS="${ENABLE_PRISMA_MIGRATIONS:-true}"
PRISMA_APP_DB_INDEX="${PRISMA_APP_DB_INDEX:-1}"
PRISMA_WORKDIR="${PRISMA_WORKDIR:-/workspace}"
SERVOY_USER_HOME="${SERVOY_USER_HOME:-/var/servoy-home}"
ENABLE_UNIT_TESTS="${ENABLE_UNIT_TESTS:-false}"
UNIT_TEST_SOLUTION="${UNIT_TEST_SOLUTION:-servoy_unit_tests}"
UNIT_TEST_EXPORT_DIR="${UNIT_TEST_EXPORT_DIR:-/tmp/exportedSolutions}"
UNIT_TEST_TIMEOUT_SECONDS="${UNIT_TEST_TIMEOUT_SECONDS:-300}"
UNIT_TEST_PROPERTIES_FILE="${UNIT_TEST_PROPERTIES_FILE:-/tmp/servoy-tests.properties}"
REPOSITORY_DB_NAME="repository_server"
REPOSITORY_DB_HOST="${REPOSITORY_DB_HOST:-127.0.0.1}"
REPOSITORY_DB_PORT="${REPOSITORY_DB_PORT:-3306}"
REPOSITORY_DB_USER="${REPOSITORY_DB_USER:-repository_user}"
REPOSITORY_DB_PASSWORD="${REPOSITORY_DB_PASSWORD:-}"

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

ensure_repository_server_mapping() {
  properties_file="$1"
  repository_index="$2"

  if grep -Eq '^repository_server=' "${properties_file}" || grep -Eq '^server\.[0-9]+\.server[Nn]ame=repository_server$' "${properties_file}"; then
    return
  fi

  require_env REPOSITORY_DB_HOST
  require_env REPOSITORY_DB_USER

  echo "==> repository_server mapping not found, appending it to ${properties_file}."

  printf "\n" >> "${properties_file}"
  cat >> "${properties_file}" <<EOF
repository_server=server.${repository_index}
server.${repository_index}.serverName=repository_server
server.${repository_index}.URL=jdbc:mysql://${REPOSITORY_DB_HOST}:${REPOSITORY_DB_PORT}/${REPOSITORY_DB_NAME}?useUnicode=true&characterEncoding=UTF-8&useSSL=${DB_USE_SSL}&allowPublicKeyRetrieval=${DB_ALLOW_PUBLIC_KEY_RETRIEVAL}
server.${repository_index}.userName=${REPOSITORY_DB_USER}
server.${repository_index}.user=${REPOSITORY_DB_USER}
server.${repository_index}.password=${REPOSITORY_DB_PASSWORD}
server.${repository_index}.driver=com.mysql.cj.jdbc.Driver
server.${repository_index}.catalog=${REPOSITORY_DB_NAME}
server.${repository_index}.maxConnectionsActive=${DB_MAX_CONNECTIONS_ACTIVE}
server.${repository_index}.maxConnectionsIdle=${DB_MAX_CONNECTIONS_IDLE}
server.${repository_index}.maxPreparedStatementsIdle=${DB_MAX_PREPARED_STATEMENTS_IDLE}
server.${repository_index}.connectionValidationType=${DB_CONNECTION_VALIDATION_TYPE}
server.${repository_index}.validationQuery=select 1
server.${repository_index}.clientOnlyConnections=${DB_CLIENT_ONLY_CONNECTIONS}
server.${repository_index}.prefixTables=${DB_PREFIX_TABLES}
server.${repository_index}.queryProcedures=${DB_QUERY_PROCEDURES}
server.${repository_index}.schema=${DB_SCHEMA}
server.${repository_index}.skipSysTables=${DB_SKIP_SYS_TABLES}
EOF
}

append_mysql_server_mapping() {
  properties_file="$1"
  server_index="$2"
  server_name="$3"
  host="$4"
  port="$5"
  db_name="$6"
  db_user="$7"
  db_password="$8"

  printf "\n" >> "${properties_file}"
  cat >> "${properties_file}" <<EOF
server.${server_index}.serverName=${server_name}
server.${server_index}.URL=jdbc:mysql://${host}:${port}/${db_name}?useUnicode=true&characterEncoding=UTF-8&useSSL=${DB_USE_SSL}&allowPublicKeyRetrieval=${DB_ALLOW_PUBLIC_KEY_RETRIEVAL}
server.${server_index}.userName=${db_user}
server.${server_index}.user=${db_user}
server.${server_index}.password=${db_password}
server.${server_index}.driver=com.mysql.cj.jdbc.Driver
server.${server_index}.catalog=${db_name}
server.${server_index}.maxConnectionsActive=${DB_MAX_CONNECTIONS_ACTIVE}
server.${server_index}.maxConnectionsIdle=${DB_MAX_CONNECTIONS_IDLE}
server.${server_index}.maxPreparedStatementsIdle=${DB_MAX_PREPARED_STATEMENTS_IDLE}
server.${server_index}.connectionValidationType=${DB_CONNECTION_VALIDATION_TYPE}
server.${server_index}.validationQuery=select 1
server.${server_index}.clientOnlyConnections=${DB_CLIENT_ONLY_CONNECTIONS}
server.${server_index}.prefixTables=${DB_PREFIX_TABLES}
server.${server_index}.queryProcedures=${DB_QUERY_PROCEDURES}
server.${server_index}.schema=${DB_SCHEMA}
server.${server_index}.skipSysTables=${DB_SKIP_SYS_TABLES}
EOF
}

append_application_server_mappings() {
  properties_file="$1"
  next_index="$2"

  app_prefixes=$(env | awk -F= '/^APP_DB_[0-9]+_SERVER_NAME=/{print $1}' | sed 's/_SERVER_NAME$//' | sort -t_ -k3,3n)
  if [ -z "${app_prefixes}" ]; then
    echo "ERROR: At least one application DB is required (APP_DB_1_SERVER_NAME, APP_DB_1_HOST, APP_DB_1_NAME, APP_DB_1_USER)." >&2
    exit 1
  fi

  for prefix in ${app_prefixes}; do
    eval "app_server_name=\${${prefix}_SERVER_NAME:-}"
    eval "app_host=\${${prefix}_HOST:-}"
    eval "app_port=\${${prefix}_PORT:-3306}"
    eval "app_name=\${${prefix}_NAME:-}"
    eval "app_user=\${${prefix}_USER:-}"
    eval "app_password=\${${prefix}_PASSWORD:-}"

    if [ -z "${app_server_name}" ] || [ -z "${app_host}" ] || [ -z "${app_name}" ] || [ -z "${app_user}" ]; then
      echo "ERROR: ${prefix}_SERVER_NAME, ${prefix}_HOST, ${prefix}_NAME and ${prefix}_USER are required." >&2
      exit 1
    fi

    append_mysql_server_mapping "${properties_file}" "${next_index}" "${app_server_name}" "${app_host}" "${app_port}" "${app_name}" "${app_user}" "${app_password}"
    next_index=$((next_index + 1))
  done

  echo "${next_index}"
}

max_server_index_from_properties() {
  properties_file="$1"
  max_server_index=$(grep -Eo '^server\.[0-9]+\.server[Nn]ame=' "${properties_file}" | sed -E 's/^server\.([0-9]+)\..*/\1/' | sort -n | tail -1)
  if [ -z "${max_server_index}" ]; then
    max_server_index=-1
  fi
  echo "${max_server_index}"
}

sync_server_count() {
  properties_file="$1"
  max_server_index=$(max_server_index_from_properties "${properties_file}")
  number_of_servers=$((max_server_index + 1))

  if grep -q '^ServerManager.numberOfServers=' "${properties_file}"; then
    sed -i "s/^ServerManager.numberOfServers=.*/ServerManager.numberOfServers=${number_of_servers}/" "${properties_file}"
  else
    printf "ServerManager.numberOfServers=%s\n" "${number_of_servers}" >> "${properties_file}"
  fi
}

run_prisma_migrations() {
  if [ "${ENABLE_PRISMA_MIGRATIONS}" != "true" ]; then
    echo "==> ENABLE_PRISMA_MIGRATIONS=false, skipping Prisma migrations."
    return
  fi

  prisma_bin="${PRISMA_WORKDIR}/node_modules/.bin/prisma"
  if [ ! -x "${prisma_bin}" ]; then
    echo "ERROR: Prisma CLI not found at '${prisma_bin}'." >&2
    exit 1
  fi

  app_prefix="APP_DB_${PRISMA_APP_DB_INDEX}"
  eval "app_server_name=\${${app_prefix}_SERVER_NAME:-}"
  eval "app_host=\${${app_prefix}_HOST:-}"
  eval "app_port=\${${app_prefix}_PORT:-3306}"
  eval "app_name=\${${app_prefix}_NAME:-}"
  eval "app_user=\${${app_prefix}_USER:-}"
  eval "app_password=\${${app_prefix}_PASSWORD:-}"
  eval "app_database_url=\${${app_prefix}_DATABASE_URL:-}"

  if [ -z "${app_server_name}" ] || [ -z "${app_host}" ] || [ -z "${app_name}" ] || [ -z "${app_user}" ]; then
    echo "ERROR: ${app_prefix}_SERVER_NAME, ${app_prefix}_HOST, ${app_prefix}_NAME and ${app_prefix}_USER are required for Prisma migration." >&2
    exit 1
  fi

  prisma_schema_file="${PRISMA_WORKDIR}/prisma/${app_server_name}/schema.prisma"
  if [ ! -f "${prisma_schema_file}" ]; then
    echo "ERROR: Prisma schema file not found: ${prisma_schema_file}" >&2
    exit 1
  fi

  if [ "${ENABLE_LOCAL_MYSQL}" = "true" ]; then
    echo "==> Ensuring Prisma app database '${app_name}' exists..."
    mysql_root -e "CREATE DATABASE IF NOT EXISTS \`${app_name}\`;"

    if [ -n "${app_user}" ]; then
      echo "==> Ensuring Prisma app database user '${app_user}'..."
      mysql_root \
        -e "CREATE USER IF NOT EXISTS '${app_user}'@'%' IDENTIFIED BY '${app_password}';" \
        -e "GRANT ALL PRIVILEGES ON \`${app_name}\`.* TO '${app_user}'@'%';" \
        -e "FLUSH PRIVILEGES;"
    fi
  fi

  if [ -n "${app_database_url}" ]; then
    database_url="${app_database_url}"
  else
    database_url="mysql://${app_user}:${app_password}@${app_host}:${app_port}/${app_name}"
  fi

  echo "==> Applying Prisma migrations for '${app_server_name}'..."
  APPDB_DATABASE_URL="${database_url}" "${prisma_bin}" migrate deploy --config "${PRISMA_WORKDIR}/prisma.appdb.config.ts" --schema "${prisma_schema_file}"
}

run_unit_tests() {
  if [ "${ENABLE_UNIT_TESTS}" != "true" ]; then
    echo "==> ENABLE_UNIT_TESTS=false, skipping JSUnit tests."
    return
  fi

  echo "==> Exporting test solution '${UNIT_TEST_SOLUTION}' for JSUnit runner..."
  rm -rf "${UNIT_TEST_EXPORT_DIR}"
  mkdir -p "${UNIT_TEST_EXPORT_DIR}"

  cp "${WAR_PROPERTIES_FILE}" "${UNIT_TEST_PROPERTIES_FILE}"
  if grep -q '^servoy.log.clientstats=' "${UNIT_TEST_PROPERTIES_FILE}"; then
    sed -i 's/^servoy\.log\.clientstats=.*/servoy.log.clientstats=false/' "${UNIT_TEST_PROPERTIES_FILE}"
  else
    printf "\nservoy.log.clientstats=false\n" >> "${UNIT_TEST_PROPERTIES_FILE}"
  fi

  "${SOLUTION_EXPORTER}" \
    -s "${UNIT_TEST_SOLUTION}" \
    -o "${UNIT_TEST_EXPORT_DIR}" \
    -data "${SOURCE_DIR}" \
    -modules \
    -p "${UNIT_TEST_PROPERTIES_FILE}" \
    -as "${SERVOY_HOME}/application_server" \
    ${UNIT_TEST_EXPORT_EXTRA_ARGS:-}

  jsunit_plugin_jar=$(ls "${SERVOY_HOME}"/developer/plugins/com.servoy.eclipse.jsunit_*.jar 2>/dev/null | head -n 1)
  if [ -z "${jsunit_plugin_jar}" ]; then
    echo "ERROR: Could not find com.servoy.eclipse.jsunit plugin jar in ${SERVOY_HOME}/developer/plugins." >&2
    exit 1
  fi

  rm -f /tmp/j2db_test.jar /tmp/jsunit-1.3.jar
  jar xf "${jsunit_plugin_jar}" j2db_test.jar jsunit-1.3.jar
  if [ ! -f "j2db_test.jar" ] || [ ! -f "jsunit-1.3.jar" ]; then
    echo "ERROR: Could not extract required JSUnit runner jars from ${jsunit_plugin_jar}." >&2
    exit 1
  fi
  mv j2db_test.jar /tmp/j2db_test.jar
  mv jsunit-1.3.jar /tmp/jsunit-1.3.jar

  echo "==> Running JSUnit tests from exports in '${UNIT_TEST_EXPORT_DIR}'..."
  jsunit_log="/tmp/jsunit-run.log"
  jsunit_exit=0
  (
    cd "${SERVOY_HOME}/application_server" || exit 1
    java \
      -Djava.awt.headless=true \
      -Dservoy.application_server.dir="${SERVOY_HOME}/application_server" \
      -Dservoy.test.property-file="${UNIT_TEST_PROPERTIES_FILE}" \
      -Dservoy.test.target-exports="${UNIT_TEST_EXPORT_DIR}" \
      -Dservoy.test.solution-load.timeout="${UNIT_TEST_TIMEOUT_SECONDS}" \
      ${UNIT_TEST_JAVA_OPTS:-} \
      -cp "/tmp/j2db_test.jar:/tmp/jsunit-1.3.jar:${SERVOY_HOME}/developer/plugins/*:${SERVOY_HOME}/application_server/lib/*" \
      com.servoy.j2db.importrunner.jsunit.ServoyJSUnitTestRunner
  ) >"${jsunit_log}" 2>&1 || jsunit_exit=$?

  cat "${jsunit_log}"

  if [ "${jsunit_exit}" -ne 0 ]; then
    echo "ERROR: JSUnit runner exited with code ${jsunit_exit}." >&2
    exit "${jsunit_exit}"
  fi

  if grep -Eq 'FAILURES!!!|Tests run: [0-9]+, +Failures: [1-9][0-9]*|Tests run: [0-9]+, +Failures: [0-9]+, +Errors: [1-9][0-9]*' "${jsunit_log}"; then
    echo "ERROR: JSUnit test failures detected." >&2
    exit 1
  fi

  echo "==> JSUnit stage completed."
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

  echo "==> Ensuring repository database '${REPOSITORY_DB_NAME}' exists..."
  mysql_root -e "CREATE DATABASE IF NOT EXISTS \`${REPOSITORY_DB_NAME}\`;"

  if [ -n "${REPOSITORY_DB_USER}" ]; then
    echo "==> Ensuring repository MySQL user '${REPOSITORY_DB_USER}'..."
    mysql_root \
      -e "CREATE USER IF NOT EXISTS '${REPOSITORY_DB_USER}'@'%' IDENTIFIED BY '${REPOSITORY_DB_PASSWORD}';" \
      -e "GRANT ALL PRIVILEGES ON \`${REPOSITORY_DB_NAME}\`.* TO '${REPOSITORY_DB_USER}'@'%';" \
      -e "FLUSH PRIVILEGES;"
  fi

  echo "==> Verifying MySQL query readiness..."
  i=0
  while [ "${i}" -lt 30 ]; do
    if mysql_root -e "USE \`${REPOSITORY_DB_NAME}\`; SELECT 1;" >/dev/null 2>&1; then
      echo "==> MySQL is active and repository database '${REPOSITORY_DB_NAME}' is queryable."
      break
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

run_prisma_migrations

echo "==> Preparing WAR properties from template..."
if [ -f "${WAR_PROPERTIES_TEMPLATE}" ]; then
  require_env REPOSITORY_DB_HOST
  require_env REPOSITORY_DB_USER
  cp "${WAR_PROPERTIES_TEMPLATE}" "${WAR_PROPERTIES_FILE}"
  next_server_index=$(append_application_server_mappings "${WAR_PROPERTIES_FILE}" 0)
  ensure_repository_server_mapping "${WAR_PROPERTIES_FILE}" "${next_server_index}"
  sync_server_count "${WAR_PROPERTIES_FILE}"
else
  cp "${SERVOY_HOME}/application_server/servoy.properties" "${WAR_PROPERTIES_FILE}"
fi

echo "==> Using local Servoy workspace at '${SOURCE_DIR}'."
mkdir -p "${SERVOY_USER_HOME}"
chmod 0777 "${SERVOY_USER_HOME}"

run_unit_tests

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
  -userHomeDirectory "${SERVOY_USER_HOME}" \
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
