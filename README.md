# [GizmoSQL](https://gizmodata.com/gizmosql) Power BI Connector

A Power Query custom connector (`.pqx`) that connects [Power BI Desktop](https://powerbi.microsoft.com/en-us/desktop/) directly to [GizmoSQL](https://gizmodata.com/gizmosql) via [ADBC](https://arrow.apache.org/adbc/) over [Arrow Flight SQL](https://arrow.apache.org/docs/format/FlightSql.html). Data flows column-natively in Apache Arrow format from server to Power BI — no row/column conversions in the driver path.

## Requirements

- **GizmoSQL server `≥ v1.23.0`** for the v2.x connector. v1.23.0 is the first release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns` responses; without it, Power BI surfaces "Unable to understand the type for column" the moment you click into a table in the Navigator. Connection and table-tree navigation will still succeed against older servers, so the failure is visible but localized — upgrade the server to resolve.
- **Power BI Desktop August 2025+** for the bundled `Adbc.DataSource` M function used by this connector.

## Features

- **ADBC over Arrow Flight SQL** — column-native transport via the Apache Flight SQL ADBC driver; no ODBC dependency
- **DirectQuery support** — live queries against GizmoSQL without data import
- **Hierarchical navigation** — browse databases > schemas > tables in the Navigator pane
- **Query folding** — Power BI pushes filters, joins, and aggregations down as SQL (`LIMIT`/`OFFSET`, `CAST`, SQL-92)
- **DuckDB-native SQL generator** — emits `date_trunc`, `date_diff`, `to_<unit>(n)` interval functions, `epoch_us`, etc., matching GizmoSQL's DuckDB dialect
- **Authentication** — username/password (Basic) or bearer-token (Key)
- **Signed connector** — `.pqx` is code-signed for integrity verification

## Installation

### MSI Installer (recommended)

1. Download `GizmoSQL-PowerBI-Setup-x64.msi` from the [latest release](https://github.com/gizmodata/gizmosql-powerbi-connector/releases/latest)
2. Run the installer — it installs the Apache Flight SQL ADBC driver DLL (`libadbc_driver_flightsql.dll`) to `Program Files\GizmoSQL Power BI Connector\` and adds it to the system `PATH`, drops the signed connector into Power BI's Custom Connectors directory, and registers the signing certificate as trusted with Power BI
3. Restart Power BI Desktop
4. The connector appears under **Get Data > Database > GizmoSQL**

No security setting changes required — the installer works with Power BI's default "Recommended" security level.

### Signed `.pqx` (manual)

1. Place the Apache Flight SQL ADBC driver `libadbc_driver_flightsql.dll` somewhere on the system `PATH`. The driver ships as a `.so`-named file inside the [Apache ADBC Python wheel for Windows](https://github.com/apache/arrow-adbc/releases/latest); extract `libadbc_driver_flightsql.so` from the wheel and rename it to `libadbc_driver_flightsql.dll`.
2. Download `GizmoSQL.pqx` from the [latest release](https://github.com/gizmodata/gizmosql-powerbi-connector/releases/latest)
3. Copy to `[Documents]\Power BI Desktop\Custom Connectors\` (create the folder if it doesn't exist)
4. Restart Power BI Desktop

> **Note:** When installing the `.pqx` manually (without the MSI), Power BI may show a security warning because the signing certificate is not registered as trusted. To resolve this, either use the MSI installer above, or change **File > Options > Security > Data Extensions** to **(Not Recommended) Allow any extension to load without validation or warning**.

### Unsigned `.mez` (development only)

1. Place `libadbc_driver_flightsql.dll` on the system `PATH` (see step 1 above)
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
   - **Key**: enter a bearer token (JWT)
5. Click **Connect** and browse the Navigator tree

> **OAuth (browser-flow SSO)** was supported in v1.x via the GizmoSQL ODBC driver's internal `/oauth/initiate` + poll handshake. The v2.x ADBC driver path doesn't have that hook yet; OAuth will return once a GizmoSQL-specific Go ADBC driver (vendoring `apache/arrow-adbc/go/adbc/driver/flightsql` + GizmoSQL's external-auth flow) ships.

## Authentication Methods

| Method | ADBC connection options | Use Case |
|--------|------------------------|----------|
| Username/Password (Basic) | `username`, `password` | Standard database credentials; the Apache Flight SQL ADBC driver handshakes to obtain a bearer token from the server |
| Key (Bearer Token) | `adbc.flight.sql.authorization_header = "Bearer <jwt>"` | Direct bearer/JWT auth (e.g., a token obtained out-of-band from your IdP or via a separate CLI tool) |

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
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","FlightSqlAdbcConfig.pqm","SqlGenerator.pqm","SqlGeneratorCommon.pqm","TypeInfo.pqm","resources.resx" $staging
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
        └── libadbc_driver_flightsql.dll (Apache Flight SQL ADBC driver)
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

The connector is a Power Query M language section document that calls `Adbc.DataSource()` with a Flight SQL configuration plus a custom `SqlGenerator` (`SqlGenerator.pqm`) targeting [GizmoSQL](https://gizmodata.com/gizmosql)'s DuckDB dialect. The SQL generator emits DuckDB-native idioms (`date_trunc`, `date_diff`, `to_<unit>(n)` interval functions, `epoch_us`, `make_time`, `microsecond`, `instr`, `substring + concat`, `CAST(... AS VARCHAR)`) — verified against DuckDB locally via `tests/duckdb-folding.sql`.

## License

Apache-2.0
