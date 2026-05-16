# Servoy WAR Exporter Reference

This is a practical reference for `war_export.sh` based on the exporter CLI help output and how this repository invokes it.

## Quick Start

### Canonical CLI form

```sh
war_export.sh \
  -s MySolution \
  -o /tmp \
  -data /workspace \
  -defaultAdminUser admin \
  -defaultAdminPassword admin
```

### How this repo runs it

`docker/entrypoint.sh` currently calls the exporter with:

```sh
-s "${PROJECT_NAME}" -o "/tmp" -data "${WORKSPACE_DIR}" -warFileName "servoy-app" \
-as "${SERVOY_HOME}/application_server" -pluginLocations "${SERVOY_HOME}/developer/plugins" \
-defaultAdminUser "${WAR_ADMIN_USER:-admin}" -defaultAdminPassword "${WAR_ADMIN_PASSWORD:-admin}"
```

You can override export admin credentials via env vars:

```sh
docker run --rm \
  -e REPO_URL=https://github.com/org/servoy-project \
  -e PROJECT_NAME=MySolution \
  -e WAR_ADMIN_USER=admin \
  -e WAR_ADMIN_PASSWORD=admin \
  servoy-test
```

## Required Arguments

- `-s <solution_name> -o <out_dir> -data <workspace_location>` (canonical form)
- `-defaultAdminUser <user>`
- `-defaultAdminPassword <password>`

Notes:
- `-s` supports multiple solutions separated by commas.
- If multiple solutions are used, one WAR is generated per solution.

## High-Value Optional Arguments

### Build and validation behavior

- `-verbose` : verbose logging
- `-ie` : ignore build errors (**discouraged**)
- `-sb` : skip build (**discouraged**)
- `-dbi` : export from DBI files even if DB servers are available

### Export content selection

- `-active true|false` : include solution/modules in WAR (default `true`)
- `-d <jdbc_drivers>` : include only listed drivers (`<none>` allowed)
- `-excludeDrivers <jdbc_drivers>` : exclude listed drivers
- `-pi <plugin_names>` : include only listed plugins (`<none>` allowed)
- `-excludePlugins <plugin_names>` : exclude listed plugins
- `-crefs [all|components...]` : export only used components (+ optional extras)
- `-excludeComponentPkgs <pkgs...>` : exclude component packages
- `-srefs [all|services...]` : export only used services (+ optional extras)
- `-excludeServicePkgs <pkgs...>` : exclude service packages
- `-nas <solutions...>` : export non-active solutions too

### Data export

- `-md` : export metadata tables
- `-checkmd` : verify metadata consistency before export (only with `-md`)
- `-sd` : export sample data (DB servers must be running)
- `-sdcount <count|all>` : sample data row limit (default `5000`)
- `-i18n` : export i18n data
- `-users` : export users
- `-tables` : export referenced server table info (DB servers must be running)

### Naming and packaging

- `-warFileName <name>` : explicit WAR filename (not for multi-solution export)
- `-contextFileName <path>` : include Tomcat `context.xml` as `WAR/META-INF/context.xml`
- `-log4jConfigurationFile <path>` : include custom log4j config
- `-webXmlFileName <path>` : include custom `web.xml`
- `-ng2 true|false|sourcemaps` : Titanium NG2 binaries export (default `true`)

### Deployment/admin behavior

- `-importUserPolicy 0|1|2` : user/group import policy (`1` default)
- `-addUsersToAdminGroup`
- `-overwriteGroups`
- `-useAsRealAdminUser`
- `-upgradeRepository`
- `-updateSequences`
- `-overrideSequenceTypes`
- `-overrideDefaultValues`
- `-insertNewI18NKeysOnly`
- `-allowSQLKeywords`
- `-stopOnDataModelChanges`
- `-allowDataModelChanges [server_names...]`
- `-skipDatabaseViewsUpdate`

### Properties and paths

- `-p <properties_file>` : exporter startup properties (`application_server/servoy.properties` default)
- `-pfw <properties_file>` : properties file included inside WAR (same default)
- `-as <app_server_dir>` : application server directory (default `../../application_server`)
- `-pl` : allow deep search in workspace subfolders for projects/resources
- `-pluginLocations <absolute_paths...>` : plugin lookup override
- `-userHomeDirectory <path>` : writable Servoy home
- `-doNotOverwriteDBServerProperties` : preserve changed DB server props from deployed app
- `-overwriteAllProperties` : force overwrite all properties from exported WAR

### License arguments

Single license form:
- `-license.company_name <name>`
- `-license.code <code>`
- `-license.licenses <count|SERVER>`

Multiple license form:
- `-license.1.company_name ... -license.1.code ... -license.1.licenses ...`
- `-license.2.company_name ... -license.2.code ... -license.2.licenses ...`

## Common Errors and Fixes

### `Parameters'-defaultAdminUser' and '-defaultAdminPassword' are required`

Add both parameters, for example through `WAR_EXTRA_ARGS` in this repo.

### `Solution name(s) was(were) not specified after '-s' argument`

When invoking exporter directly in canonical mode, provide `-s`.

### `Export file path was not specified after '-o' argument`

When invoking exporter directly in canonical mode, provide `-o`.

## Exit Codes

- `0` normal
- `1` export stopped by user
- `2` export failed
- `3` invalid arguments
