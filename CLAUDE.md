# GizmoSQL Power BI Connector

## Architecture

Power Query M connector wrapping `Adbc.DataSource()` for the Apache Arrow Flight SQL ADBC driver.

```
Power BI Desktop
    └── GizmoSQL.pqx (this connector)
        └── libadbc_driver_flightsql.dll (Apache Arrow Flight SQL ADBC driver)
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

## Key Files

- `GizmoSQL.pq` — Main connector source (M language section document)
- `GizmoSQL.query.pq` — Test query for Power Query SDK
- `Diagnostics.pqm` — Trace logging module
- `FlightSqlAdbcConfig.pqm` — ADBC driver config (DLL name, entry point, capabilities)
- `SqlGenerator.pqm` / `SqlGeneratorCommon.pqm` / `TypeInfo.pqm` — SQL-92 query folding generator (adapted from spiceai/powerbi-connector, MIT)
- `resources.resx` — Localized strings (button text, labels)
- `icons/` — Connector icons (16px–64px PNG)

## Build

```powershell
# Create unsigned .mez for development
$staging = New-Item -ItemType Directory -Path "staging" -Force
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","FlightSqlAdbcConfig.pqm","SqlGenerator.pqm","SqlGeneratorCommon.pqm","TypeInfo.pqm","resources.resx" $staging
Copy-Item "icons\*.png" $staging
Compress-Archive -Path "staging\*" -DestinationPath "GizmoSQL.zip"
Rename-Item "GizmoSQL.zip" "GizmoSQL.mez" -Force
```

The Apache Flight SQL ADBC driver (`libadbc_driver_flightsql.dll`) must be installed/discoverable by Power BI Desktop separately — it's not bundled in the `.mez`. Get it from `apache/arrow-adbc` releases.

Install to: `[Documents]\Power BI Desktop\Custom Connectors\`

## Key Patterns

### Adbc.DataSource Options
Query folding is driven by the `SqlGenerator` passed to `Adbc.DataSource`. The generator (`SqlGenerator.pqm`) is built on top of the Sql92 base via `SqlGeneratorHelpers[MergeOverrides]("Sql92", Override, false)` and includes function overrides for date/time, casts, aggregates, etc. `LimitClauseKind = LimitClauseKind.LimitOffset` is the key folding capability for GizmoSQL.

### Trace Logging
`EnableTraceOutput` (line 5 in `GizmoSQL.pq`) controls the Diagnostics module. Set to `false` for production, `true` for development. When enabled, traces appear in Power BI's Mashup Container logs at `%LOCALAPPDATA%\Microsoft\Power BI Desktop\Traces\`.

### Authentication
The connector supports two auth kinds via `Extension.CurrentCredential()`, mapped to Flight SQL ADBC connection options:
- `UsernamePassword` → `username` / `password`
- `Key` → `adbc.flight.sql.authorization_header = "Bearer <token>"`

OAuth (browser-flow SSO) was supported on the v1.x ODBC connector via `authType=external`, where the ODBC driver handled the `/oauth/initiate` + poll dance internally. The generic Apache Flight SQL ADBC driver bundled in v2.x has no such hook, so OAuth is removed for now. The plan is to ship a GizmoSQL-specific Go ADBC driver that vendors `apache/arrow-adbc/go/adbc/driver/flightsql` and adds the external-auth flow — at which point we re-add `Implicit` here as a one-line flag mapping (mirroring how it worked on the ODBC connector).

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
