# GizmoSQL Power BI Connector

## Architecture

Power Query M connector built on the newer (experimental) ADBC extensibility APIs — `Adbc.Connection()` + `SqlView.Generator()` — driving the Apache Arrow Flight SQL ADBC driver.

```
Power BI Desktop
    └── GizmoSQL.pqx (this connector)
        └── libadbc_driver_flightsql.dll (Apache Arrow Flight SQL ADBC driver)
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

## Key Files

- `GizmoSQL.pq` — Main connector source (M language section document): driver record, `Adbc.Connection` setup, navigation tables, OAuth handlers
- `GizmoSQL.query.pq` — Test query for Power Query SDK
- `Diagnostics.pqm` — Trace logging module
- `SqlGenerator.pqm` / `SqlGeneratorCommon.pqm` — DuckDB query folding generator (vendored from CurtHagenlocher/quack-net, Apache-2.0, via PR #3; `Text.*` predicate folds carried over from the earlier spiceai/powerbi-connector lineage, MIT)
- `resources.resx` — Localized strings (button text, labels)
- `icons/` — Connector icons (16px–64px PNG)

## Build

```powershell
# Create unsigned .mez for development
$staging = New-Item -ItemType Directory -Path "staging" -Force
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","SqlGenerator.pqm","SqlGeneratorCommon.pqm","resources.resx" $staging
Copy-Item "icons\*.png" $staging
Compress-Archive -Path "staging\*" -DestinationPath "GizmoSQL.zip"
Rename-Item "GizmoSQL.zip" "GizmoSQL.mez" -Force
```

The Apache Flight SQL ADBC driver (`libadbc_driver_flightsql.dll`) must be installed/discoverable by Power BI Desktop separately — it's not bundled in the `.mez`. Get it from `apache/arrow-adbc` releases.

Install to: `[Documents]\Power BI Desktop\Custom Connectors\`

## Key Patterns

### Adbc.Connection + SqlView.Generator (experimental APIs)
The connector uses the newer ADBC extensibility surface instead of `Adbc.DataSource`: `Adbc.Connection(Driver, DatabaseProperties, ConnectionProperties, [ConnectionPoolType = 2])` opens the driver, and `SqlView.Generator(UniqueIdentifier, GizmoSqlGenerator, GetData)` wires query folding. The `UniqueIdentifier` (first argument) is what the mashup engine compares to decide whether two queries point at the same data source — it is keyed on the connection target (URI + default catalog), **never credentials**, so all tables from one connection share one identity and cross-table joins fold in DirectQuery (the `Adbc.DataSource` blocker in issue #2 / microsoft/vscode-powerquery-sdk#409). These APIs are experimental per Microsoft (mattmasson) and may change across Power BI Desktop releases. The Navigator is hand-rolled from `information_schema` / `pragma_table_info` queries with `OnSelectRows` folding; the generator is merged over the quack-net base via `SqlGeneratorHelpers[MergeOverrides]` with DuckDB-specific overrides for date/time, casts, aggregates, and text predicates.

### Trace Logging
`EnableTraceOutput` (line 5 in `GizmoSQL.pq`) controls the Diagnostics module. Set to `false` for production, `true` for development. When enabled, traces appear in Power BI's Mashup Container logs at `%LOCALAPPDATA%\Microsoft\Power BI Desktop\Traces\`.

### Authentication
The connector supports three auth kinds via `Extension.CurrentCredential()`, mapped to Flight SQL ADBC database options:
- `UsernamePassword` → `username` / `password`
- `Key` → `adbc.flight.sql.authorization_header = "Bearer <token>"`
- `OAuth` → `adbc.flight.sql.authorization_header = "Bearer <access_token>"`

OAuth is implemented entirely in M (no driver involvement) against GizmoSQL Enterprise's server-side OAuth: `StartLogin` calls `GET /oauth/initiate` (on `--oauth-port`, default `31339`) and hands `auth_url` to Power BI's embedded browser with `CallbackUri = <base>/oauth/callback`; when the IdP redirects there, `FinishLogin` replays the callback request (in case the browser was closed before the server processed the code exchange) and polls `GET /oauth/token/{session_uuid}` (`IsRetry = true` to bypass the M request cache; `Function.InvokeAfter` between attempts) until `status = "complete"`. Caveats: `Web.Contents` cannot skip TLS verification, so the OAuth endpoint's cert must be client-trusted; no refresh token, so expired JWTs require interactive re-auth (scheduled refresh on a gateway will prompt).

## Changelog
- **Always update `CHANGELOG.md`** when making changes — bug fixes, new features, behavioral changes, or breaking changes
- Follow [Keep a Changelog](https://keepachangelog.com/) format
- Group changes under: Added, Changed, Fixed, Removed
- New entries go under the `## [Unreleased]` section at the top
- When tagging a release, rename `[Unreleased]` to the version and date (e.g., `## [v1.1.0] - 2026-02-25`) and add a new empty `[Unreleased]` above it
- Write entries from the user's perspective — describe the symptom/impact, not just the code change
- Include root cause details for non-obvious bug fixes so future maintainers understand the issue

## Testing
- Test with Power BI Desktop in both Import and DirectQuery modes
- Verify Navigator pane shows catalogs > schemas > tables
- Verify query folding by right-clicking a step > "View Native Query"
- Clear PBI caches between tests: `%LOCALAPPDATA%\Microsoft\Power BI Desktop\` (Cache, ExtensionCache, FoldedArtifactsCache, AnalysisServicesWorkspaces)
