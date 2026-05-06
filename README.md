# [GizmoSQL](https://gizmodata.com/gizmosql) Power BI Connector

A Power Query custom connector (`.pqx`) that wraps the [GizmoSQL ODBC driver](https://github.com/gizmodata/gizmosql-odbc-driver), enabling Power BI Desktop users to connect to [GizmoSQL](https://gizmodata.com/gizmosql) via **Get Data > Database > GizmoSQL**.

## Requirements

- **GizmoSQL server `≥ v1.23.0`** for the v2.x connector. v1.23.0 is the first release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns` responses; without it, Power BI surfaces "Unable to understand the type for column" the moment you click into a table in the Navigator. Connection and table-tree navigation will still succeed against older servers, so the failure is visible but localized — upgrade the server to resolve.
- **Power BI Desktop August 2025+** for the bundled `Adbc.DataSource` M function used by this connector.

## Features

- **DirectQuery support** — live queries against GizmoSQL without data import
- **Hierarchical navigation** — browse databases > schemas > tables in the Navigator pane
- **Query folding** — Power BI pushes filters, joins, and aggregations down as SQL (`LIMIT`/`OFFSET`, `CAST`, SQL-92)
- **Authentication** — username/password, token-based, or OAuth (browser) auth
- **Signed connector** — `.pqx` is code-signed for integrity verification

## Installation

### MSI Installer (recommended)

1. Download `GizmoSQL-PowerBI-Setup-x64.msi` from the [latest release](https://github.com/gizmodata/gizmosql-powerbi-connector/releases/latest)
2. Run the installer — it installs the ODBC driver, the signed connector, and registers the signing certificate as trusted with Power BI
3. Restart Power BI Desktop
4. The connector appears under **Get Data > Database > GizmoSQL**

No security setting changes required — the installer works with Power BI's default "Recommended" security level.

### Signed `.pqx` (manual)

1. Install the [GizmoSQL ODBC Driver](https://github.com/gizmodata/gizmosql-odbc-driver/releases)
2. Download `GizmoSQL.pqx` from the [latest release](https://github.com/gizmodata/gizmosql-powerbi-connector/releases/latest)
3. Copy to `[Documents]\Power BI Desktop\Custom Connectors\` (create the folder if it doesn't exist)
4. Restart Power BI Desktop

> **Note:** When installing the `.pqx` manually (without the MSI), Power BI may show a security warning because the signing certificate is not registered as trusted. To resolve this, either use the MSI installer above, or change **File > Options > Security > Data Extensions** to **(Not Recommended) Allow any extension to load without validation or warning**.

### Unsigned `.mez` (development only)

1. Install the [GizmoSQL ODBC Driver](https://github.com/gizmodata/gizmosql-odbc-driver/releases)
2. Download `GizmoSQL.mez` from the [latest release](https://github.com/gizmodata/gizmosql-powerbi-connector/releases/latest)
3. Copy to `[Documents]\Power BI Desktop\Custom Connectors\`
4. In Power BI Desktop, go to **File > Options > Security > Data Extensions** and select **(Not Recommended) Allow any extension to load without validation or warning**
5. Restart Power BI Desktop

## Connecting

1. Open Power BI Desktop
2. Click **Get Data > Database > GizmoSQL**
3. Enter:
   - **Server**: hostname or IP address (e.g., `localhost`)
   - **Port**: port number (e.g., `31337`)
4. Choose an authentication method:
   - **Username/Password**: enter your GizmoSQL credentials
   - **Key**: enter a bearer token
   - **OAuth (Browser)**: authenticate via your identity provider in a browser window
5. Click **Connect** and browse the Navigator tree

## Authentication Methods

| Method | ODBC Parameters | Use Case |
|--------|----------------|----------|
| Username/Password | `UID`, `PWD`, `authType=basic` | Standard database credentials |
| Key (Token) | `token`, `authType=token` | Bearer token / JWT authentication |
| OAuth (Browser) | `authType=external` | SSO via identity provider (opens browser for login) |

## DirectQuery

To use DirectQuery mode (live queries without data import):

1. Connect to GizmoSQL as described above
2. When prompted, select **DirectQuery** instead of **Import**
3. Build your report — each visual generates live SQL queries

### Query Folding

The connector declares GizmoSQL's SQL capabilities so Power BI can fold transformations into native SQL:

- `LIMIT` / `OFFSET` (not `TOP`)
- `CAST` (not `CONVERT`)
- Full SQL-92 compliance
- Derived tables (subqueries in `FROM`)
- All standard aggregate functions

To verify query folding, right-click a step in the Power Query Editor and select **View Native Query**.

## Development

### Building locally

```powershell
# Create .mez by zipping connector files
$staging = New-Item -ItemType Directory -Path "staging" -Force
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","OdbcConstants.pqm","resources.resx" $staging
Copy-Item "icons\*.png" $staging
Compress-Archive -Path "staging\*" -DestinationPath "GizmoSQL.zip"
Rename-Item "GizmoSQL.zip" "GizmoSQL.mez" -Force
```

### Testing with Docker

```bash
# Start a GizmoSQL instance
docker run -p 31337:31337 \
  -e GIZMOSQL_USERNAME=gizmosql_user \
  -e GIZMOSQL_PASSWORD=gizmosql_password \
  -e TLS_ENABLED=0 \
  gizmodata/gizmosql:latest
```

Then connect in Power BI with server `localhost`, port `31337`, username `gizmosql_user`, password `gizmosql_password`.

## Architecture

```
Power BI Desktop
    └── GizmoSQL.pqx (this connector)
        └── GizmoSQL ODBC Driver
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

The connector is a Power Query M language section document that wraps `Odbc.DataSource()`, declaring [GizmoSQL](https://gizmodata.com/gizmosql)'s SQL dialect capabilities so Power BI generates compatible SQL for query folding and DirectQuery.

## License

Apache-2.0
