#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-}"
SOURCE_DIR="${SOURCE_DIR:-${ROOT_DIR}/src}"
SERVOY_DIST_GLOB="${SERVOY_DIST_GLOB:-${ROOT_DIR}/artifacts/servoy_linux.*.tar.gz}"
SERVOY_HOME="${SERVOY_HOME:-${ROOT_DIR}/_ci/tools/servoy}"
SERVOY_USER_HOME="${SERVOY_USER_HOME:-${ROOT_DIR}/_ci/tools/servoy-user-home}"
PRISMA_WORKDIR="${PRISMA_WORKDIR:-${ROOT_DIR}}"
WAR_OUTPUT_DIR="${WAR_OUTPUT_DIR:-${ROOT_DIR}/_ci/tomcat/webapps}"
WAR_FILE_BASENAME="${WAR_FILE_BASENAME:-ROOT}"
WAR_PROPERTIES_TEMPLATE="${WAR_PROPERTIES_TEMPLATE:-${ROOT_DIR}/ci/servoy.properties.ci.template}"
WAR_PROPERTIES_FILE="${WAR_PROPERTIES_FILE:-${ROOT_DIR}/_ci/servoy.properties}"
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-http://127.0.0.1:8080/}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-60}"
HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-5}"
ENABLE_UNIT_TESTS="${ENABLE_UNIT_TESTS:-true}"
UNIT_TEST_SOLUTION="${UNIT_TEST_SOLUTION:-servoy_unit_tests}"
UNIT_TEST_EXPORT_DIR="${UNIT_TEST_EXPORT_DIR:-${ROOT_DIR}/_ci/exportedSolutions}"
UNIT_TEST_TIMEOUT_SECONDS="${UNIT_TEST_TIMEOUT_SECONDS:-300}"
UNIT_TEST_PROPERTIES_FILE="${UNIT_TEST_PROPERTIES_FILE:-${ROOT_DIR}/_ci/servoy-tests.properties}"
WAR_ADMIN_USER="${WAR_ADMIN_USER:-admin}"
WAR_ADMIN_PASSWORD="${WAR_ADMIN_PASSWORD:-admin}"
MYSQL_CONTAINER_NAME="${MYSQL_CONTAINER_NAME:-servoy-ci-mysql}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
APP_DB_1_SERVER_NAME="${APP_DB_1_SERVER_NAME:-appdb}"
APP_DB_1_HOST="${APP_DB_1_HOST:-127.0.0.1}"
APP_DB_1_PORT="${APP_DB_1_PORT:-3306}"
APP_DB_1_NAME="${APP_DB_1_NAME:-appdb}"
APP_DB_1_USER="${APP_DB_1_USER:-appuser}"
APP_DB_1_PASSWORD="${APP_DB_1_PASSWORD:-appsecret}"
REPOSITORY_DB_NAME="${REPOSITORY_DB_NAME:-repository_server}"
REPOSITORY_DB_HOST="${REPOSITORY_DB_HOST:-127.0.0.1}"
REPOSITORY_DB_PORT="${REPOSITORY_DB_PORT:-3306}"
REPOSITORY_DB_USER="${REPOSITORY_DB_USER:-repository_user}"
REPOSITORY_DB_PASSWORD="${REPOSITORY_DB_PASSWORD:-repository_secret}"

require_file() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    echo "ERROR: required file not found: ${path}" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  if [ ! -d "${path}" ]; then
    echo "ERROR: required directory not found: ${path}" >&2
    exit 1
  fi
}

ensure_node_version() {
  local node_version
  local node_major

  if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node is required for Prisma migrations." >&2
    exit 1
  fi

  node_version="$(node --version 2>/dev/null || true)"
  node_version="${node_version#v}"
  node_major="${node_version%%.*}"

  if [ -z "${node_major}" ] || [ "${node_major}" -lt 18 ]; then
    echo "ERROR: Node.js >= 18 is required for Prisma. Found '${node_version:-unknown}'." >&2
    echo "On Windows, ensure bash resolves to your current Node installation (or run this in GitHub Actions/Linux)." >&2
    exit 1
  fi
}

if [ -z "${PROJECT_NAME}" ]; then
  echo "ERROR: PROJECT_NAME is required." >&2
  exit 1
fi

require_dir "${SOURCE_DIR}"
require_file "${WAR_PROPERTIES_TEMPLATE}"
ensure_node_version

mkdir -p "${ROOT_DIR}/_ci/logs" "${ROOT_DIR}/_ci/tools" "${WAR_OUTPUT_DIR}" "${SERVOY_USER_HOME}"

wait_for_mysql() {
  local retries=60
  local delay=2
  local attempt=0

  while [ "${attempt}" -lt "${retries}" ]; do
    if docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${MYSQL_CONTAINER_NAME}" 2>/dev/null | grep -qx "healthy"; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "${delay}"
  done

  echo "ERROR: MySQL container '${MYSQL_CONTAINER_NAME}' did not become healthy." >&2
  docker logs "${MYSQL_CONTAINER_NAME}" > "${ROOT_DIR}/_ci/logs/mysql.log" 2>&1 || true
  exit 1
}

ensure_mysql_databases() {
  local root_password="${MYSQL_ROOT_PASSWORD}"
  local inspected_password
  local login_args=()
  local mode
  local mode_args=()
  local auth_ok="false"
  local attempt

  inspected_password="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${MYSQL_CONTAINER_NAME}" 2>/dev/null | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -n 1 || true)"
  if [ -n "${inspected_password}" ]; then
    root_password="${inspected_password}"
  fi

  if [ -n "${root_password}" ]; then
    login_args=(-uroot "-p${root_password}")
  else
    login_args=(-uroot)
  fi

  for attempt in $(seq 1 30); do
    for mode in socket localhost tcp; do
      case "${mode}" in
        socket) mode_args=() ;;
        localhost) mode_args=(-hlocalhost) ;;
        tcp) mode_args=(-h127.0.0.1) ;;
      esac
      if docker exec "${MYSQL_CONTAINER_NAME}" mysql "${mode_args[@]}" "${login_args[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
        login_args=("${mode_args[@]}" "${login_args[@]}")
        auth_ok="true"
        break
      fi
    done
    if [ "${auth_ok}" = "true" ]; then
      break
    fi
    sleep 2
  done

  if [ "${auth_ok}" != "true" ]; then
    echo "ERROR: unable to authenticate as MySQL root in container '${MYSQL_CONTAINER_NAME}' after retries." >&2
    docker logs "${MYSQL_CONTAINER_NAME}" > "${ROOT_DIR}/_ci/logs/mysql.log" 2>&1 || true
    exit 1
  fi

  docker exec "${MYSQL_CONTAINER_NAME}" mysql "${login_args[@]}" \
    -e "CREATE DATABASE IF NOT EXISTS \`${REPOSITORY_DB_NAME}\`;" \
    -e "CREATE USER IF NOT EXISTS '${REPOSITORY_DB_USER}'@'%' IDENTIFIED BY '${REPOSITORY_DB_PASSWORD}';" \
    -e "GRANT ALL PRIVILEGES ON \`${REPOSITORY_DB_NAME}\`.* TO '${REPOSITORY_DB_USER}'@'%';" \
    -e "CREATE DATABASE IF NOT EXISTS \`${APP_DB_1_NAME}\`;" \
    -e "CREATE USER IF NOT EXISTS '${APP_DB_1_USER}'@'%' IDENTIFIED BY '${APP_DB_1_PASSWORD}';" \
    -e "GRANT ALL PRIVILEGES ON \`${APP_DB_1_NAME}\`.* TO '${APP_DB_1_USER}'@'%';" \
    -e "FLUSH PRIVILEGES;"
}

extract_servoy() {
  local dist_file
  dist_file="$(compgen -G "${SERVOY_DIST_GLOB}" | head -n 1 || true)"
  if [ -z "${dist_file}" ]; then
    echo "ERROR: Servoy archive not found with glob '${SERVOY_DIST_GLOB}'." >&2
    exit 1
  fi

  rm -rf "${SERVOY_HOME}"
  mkdir -p "${SERVOY_HOME}"
  tar -xzf "${dist_file}" -C "${SERVOY_HOME}"
  find "${SERVOY_HOME}" -type f -name "*.sh" -exec chmod +x {} \;
}

render_servoy_properties() {
  cp "${WAR_PROPERTIES_TEMPLATE}" "${WAR_PROPERTIES_FILE}"

  if grep -q '^ServerManager.numberOfServers=' "${WAR_PROPERTIES_FILE}"; then
    sed -i 's/^ServerManager.numberOfServers=.*/ServerManager.numberOfServers=2/' "${WAR_PROPERTIES_FILE}"
  else
    printf '\nServerManager.numberOfServers=2\n' >> "${WAR_PROPERTIES_FILE}"
  fi

  cat >> "${WAR_PROPERTIES_FILE}" <<EOF
repository_server=server.1
server.0.serverName=${APP_DB_1_SERVER_NAME}
server.0.URL=jdbc:mysql://${APP_DB_1_HOST}:${APP_DB_1_PORT}/${APP_DB_1_NAME}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true
server.0.userName=${APP_DB_1_USER}
server.0.user=${APP_DB_1_USER}
server.0.password=${APP_DB_1_PASSWORD}
server.0.driver=com.mysql.cj.jdbc.Driver
server.0.catalog=${APP_DB_1_NAME}
server.1.serverName=repository_server
server.1.URL=jdbc:mysql://${REPOSITORY_DB_HOST}:${REPOSITORY_DB_PORT}/${REPOSITORY_DB_NAME}?useUnicode=true&characterEncoding=UTF-8&useSSL=false&allowPublicKeyRetrieval=true
server.1.userName=${REPOSITORY_DB_USER}
server.1.user=${REPOSITORY_DB_USER}
server.1.password=${REPOSITORY_DB_PASSWORD}
server.1.driver=com.mysql.cj.jdbc.Driver
server.1.catalog=${REPOSITORY_DB_NAME}
EOF
}

run_prisma_migrations() {
  local prisma_bin="${PRISMA_WORKDIR}/node_modules/.bin/prisma"
  require_file "${prisma_bin}"

  export APPDB_DATABASE_URL="mysql://${APP_DB_1_USER}:${APP_DB_1_PASSWORD}@${APP_DB_1_HOST}:${APP_DB_1_PORT}/${APP_DB_1_NAME}"
  "${prisma_bin}" migrate deploy --config "${PRISMA_WORKDIR}/prisma.appdb.config.ts"
}

run_jsunit_tests() {
  local solution_exporter="${SERVOY_HOME}/developer/exporter/export.sh"
  local jsunit_plugin_jar
  local jsunit_log="${ROOT_DIR}/_ci/logs/jsunit.log"

  require_file "${solution_exporter}"
  rm -rf "${UNIT_TEST_EXPORT_DIR}"
  mkdir -p "${UNIT_TEST_EXPORT_DIR}"

  cp "${WAR_PROPERTIES_FILE}" "${UNIT_TEST_PROPERTIES_FILE}"
  if grep -q '^servoy.log.clientstats=' "${UNIT_TEST_PROPERTIES_FILE}"; then
    sed -i 's/^servoy\.log\.clientstats=.*/servoy.log.clientstats=false/' "${UNIT_TEST_PROPERTIES_FILE}"
  else
    printf '\nservoy.log.clientstats=false\n' >> "${UNIT_TEST_PROPERTIES_FILE}"
  fi

  "${solution_exporter}" \
    -s "${UNIT_TEST_SOLUTION}" \
    -o "${UNIT_TEST_EXPORT_DIR}" \
    -data "${SOURCE_DIR}" \
    -modules \
    -p "${UNIT_TEST_PROPERTIES_FILE}" \
    -as "${SERVOY_HOME}/application_server"

  jsunit_plugin_jar="$(ls "${SERVOY_HOME}"/developer/plugins/com.servoy.eclipse.jsunit_*.jar 2>/dev/null | head -n 1 || true)"
  if [ -z "${jsunit_plugin_jar}" ]; then
    echo "ERROR: JSUnit plugin jar not found in '${SERVOY_HOME}/developer/plugins'." >&2
    exit 1
  fi

  rm -f /tmp/j2db_test.jar /tmp/jsunit-1.3.jar
  (
    cd /tmp
    jar xf "${jsunit_plugin_jar}" j2db_test.jar jsunit-1.3.jar
  )
  require_file "/tmp/j2db_test.jar"
  require_file "/tmp/jsunit-1.3.jar"

  (
    cd "${SERVOY_HOME}/application_server"
    java \
      -Djava.awt.headless=true \
      -Dservoy.application_server.dir="${SERVOY_HOME}/application_server" \
      -Dservoy.test.property-file="${UNIT_TEST_PROPERTIES_FILE}" \
      -Dservoy.test.target-exports="${UNIT_TEST_EXPORT_DIR}" \
      -Dservoy.test.solution-load.timeout="${UNIT_TEST_TIMEOUT_SECONDS}" \
      -cp "/tmp/j2db_test.jar:/tmp/jsunit-1.3.jar:${SERVOY_HOME}/developer/plugins/*:${SERVOY_HOME}/application_server/lib/*" \
      com.servoy.j2db.importrunner.jsunit.ServoyJSUnitTestRunner
  ) > "${jsunit_log}" 2>&1

  cat "${jsunit_log}"

  if grep -Eq 'FAILURES!!!|Tests run: [0-9]+, +Failures: [1-9][0-9]*|Tests run: [0-9]+, +Failures: [0-9]+, +Errors: [1-9][0-9]*' "${jsunit_log}"; then
    echo "ERROR: JSUnit failures were detected." >&2
    exit 1
  fi
}

build_war() {
  local war_exporter="${SERVOY_HOME}/developer/exporter/war_export.sh"
  require_file "${war_exporter}"
  mkdir -p "${WAR_OUTPUT_DIR}"

  "${war_exporter}" \
    -s "${PROJECT_NAME}" \
    -o "${WAR_OUTPUT_DIR}" \
    -data "${SOURCE_DIR}" \
    -warFileName "${WAR_FILE_BASENAME}" \
    -pfw "${WAR_PROPERTIES_FILE}" \
    -as "${SERVOY_HOME}/application_server" \
    -pluginLocations "${SERVOY_HOME}/developer/plugins" \
    -userHomeDirectory "${SERVOY_USER_HOME}" \
    -defaultAdminUser "${WAR_ADMIN_USER}" \
    -defaultAdminPassword "${WAR_ADMIN_PASSWORD}"

  require_file "${WAR_OUTPUT_DIR}/${WAR_FILE_BASENAME}.war"
}

wait_for_tomcat_health() {
  local attempt=0
  local http_code
  while [ "${attempt}" -lt "${HEALTH_CHECK_RETRIES}" ]; do
    http_code="$(curl -sS -o /dev/null -w '%{http_code}' "${HEALTH_CHECK_URL}" || true)"
    if [ "${http_code}" != "000" ] && [ -n "${http_code}" ]; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "${HEALTH_CHECK_DELAY}"
  done

  echo "ERROR: Tomcat health check failed for '${HEALTH_CHECK_URL}' (no HTTP response)." >&2
  exit 1
}

wait_for_mysql
ensure_mysql_databases
extract_servoy
render_servoy_properties
run_prisma_migrations

if [ "${ENABLE_UNIT_TESTS}" = "true" ]; then
  run_jsunit_tests
fi

build_war
wait_for_tomcat_health
