# [GizmoSQL](https://gizmodata.com/gizmosql) Power BI Connector

A Power Query custom connector (`.pqx`) that connects [Power BI Desktop](https://powerbi.microsoft.com/en-us/desktop/) directly to [GizmoSQL](https://gizmodata.com/gizmosql) via [ADBC](https://arrow.apache.org/adbc/) over [Arrow Flight SQL](https://arrow.apache.org/docs/format/FlightSql.html). Data flows column-natively in Apache Arrow format from server to Power BI — no row/column conversions in the driver path.

## Requirements

- **GizmoSQL server `≥ v1.23.0`** for the v2.x connector. v1.23.0 is the first release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns` responses; without it, Power BI surfaces "Unable to understand the type for column" the moment you click into a table in the Navigator. Connection and table-tree navigation will still succeed against older servers, so the failure is visible but localized — upgrade the server to resolve.
- **A recent Power BI Desktop build** for the bundled `Adbc.Connection` / `SqlView.Generator` M functions used by this connector (the newer — still experimental — ADBC extensibility surface, which is what enables cross-table join folding in DirectQuery).
- **GizmoSQL Enterprise** (server started with `--oauth-*` flags) if you want OAuth browser SSO; username/password and bearer-token auth work on all editions.

## Features

- **ADBC over Arrow Flight SQL** — column-native transport via the Apache Flight SQL ADBC driver; no ODBC dependency
- **DirectQuery support** — live queries against GizmoSQL without data import
- **Hierarchical navigation** — browse databases > schemas > tables in the Navigator pane
- **Query folding** — Power BI pushes filters, joins, and aggregations down as SQL (`LIMIT`/`OFFSET`, `CAST`, SQL-92)
- **DuckDB-native SQL generator** — emits `date_trunc`, `date_diff`, `to_<unit>(n)` interval functions, `epoch_us`, etc., matching GizmoSQL's DuckDB dialect
- **Authentication** — username/password (Basic), bearer-token (Key), or OAuth browser SSO (GizmoSQL Enterprise)
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
   - **OAuth (Browser)**: sign in with your identity provider via the embedded browser (requires GizmoSQL Enterprise with server-side OAuth configured)
5. Click **Connect** and browse the Navigator tree

## Authentication Methods

| Method | ADBC connection options | Use Case |
|--------|------------------------|----------|
| Username/Password (Basic) | `username`, `password` | Standard database credentials; the Apache Flight SQL ADBC driver handshakes to obtain a bearer token from the server |
| Key (Bearer Token) | `adbc.flight.sql.authorization_header = "Bearer <jwt>"` | Direct bearer/JWT auth (e.g., a token obtained out-of-band from your IdP or via a separate CLI tool) |
| OAuth (Browser) | `username = "token"`, `password = <IdP ID token>` (obtained by the connector) | Browser-flow SSO against [GizmoSQL Enterprise server-side OAuth](https://github.com/gizmodata/gizmosql/blob/main/docs/oauth_sso_setup.md): the connector calls `/oauth/initiate`, the embedded browser signs in at the IdP, and the connector polls `/oauth/token/{session}` for the IdP's ID token, which the driver presents via the Flight handshake (same `token`-username convention as JDBC); the server verifies it via JWKS and issues its own session JWT. Assumes the OAuth endpoint on `--oauth-port` `31339` (default). The OAuth endpoint's TLS certificate must be trusted by the client machine — `Web.Contents` cannot skip certificate verification |

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
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","SqlGenerator.pqm","SqlGeneratorCommon.pqm","resources.resx" $staging
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

### Debug logging

When a query fails, turn on the connector's trace output and Power BI Desktop's mashup tracing:

**1. Enable the connector's trace output** by setting `EnableTraceOutput = true` near the top of `GizmoSQL.pq` and rebuilding the `.mez` (development builds only).

**2. Enable Power BI Desktop's mashup tracing**: `File` → `Options and settings` → `Options` → `Diagnostics` → check **Enable tracing**, then restart Power BI Desktop.

**3. Reproduce the failing report.** Trace files land in:

```
%LOCALAPPDATA%\Microsoft\Power BI Desktop\Traces\
```

**4. Filter for connector entries**:

```powershell
Select-String -Path "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\Traces\*.log" -Pattern "GizmoSQL/" |
    Select-Object -ExpandProperty Line
```

What you'll see: `GizmoSQL/Connection` (server, port, default catalog — once per connection) and `GizmoSQL/OAuth/StartLogin` (OAuth base URL when the browser flow starts). `Diagnostics.pqm` also retains an `IsEnabled` marker-file helper (`C:\Users\Public\gizmosql_pbi_debug.flag`) and a `MaskCredentials` redactor from the fold-bug investigation, available for wiring up runtime-toggled instrumentation without a rebuild.

**Tip — see the folded SQL up to the breakpoint:** in **Power Query Editor**, right-click any step → **View Native Query**. Power BI shows the SQL it has folded so far. If the option is grayed out at a particular step (e.g. the join), that step is what broke folding.

To capture queries that **do** reach the server, run the GizmoSQL server with `--print-queries`:

```bash
gizmosql_server --username joe --password joe --print-queries --auth-log-level WARN --session-log-level WARN
```

A fold failure on the connector side means **no SQL reaches the server at all** — the connector log is where to look in that case.

## Architecture

```
Power BI Desktop
    └── GizmoSQL.pqx (this connector)
        └── libadbc_driver_flightsql.dll (Apache Flight SQL ADBC driver)
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

The connector is a Power Query M language section document built on the newer ADBC extensibility surface: it opens the driver with `Adbc.Connection()` and wires query folding through `SqlView.Generator()`, whose unique-identifier argument gives every table from one connection the same data-source identity — the prerequisite for folding cross-table joins in DirectQuery (see [#2](https://github.com/gizmodata/gizmosql-powerbi-connector/issues/2)). The Navigator tree is built from `information_schema` / `pragma_table_info` queries with foldable navigation steps. The SQL generator (`SqlGenerator.pqm`, vendored from [CurtHagenlocher/quack-net](https://github.com/CurtHagenlocher/quack-net), Apache-2.0, with `Text.*` predicate folds carried over from [spiceai/powerbi-connector](https://github.com/spiceai/powerbi-connector), MIT) targets [GizmoSQL](https://gizmodata.com/gizmosql)'s DuckDB dialect.

## License

Apache-2.0
