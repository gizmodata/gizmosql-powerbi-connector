# GizmoSQL Power BI Connector

## Architecture

Power Query M connector wrapping `Odbc.DataSource()` for the GizmoSQL ODBC driver.

```
Power BI Desktop
    └── GizmoSQL.pqx (this connector)
        └── GizmoSQL ODBC Driver (gizmosql-odbc.dll)
            └── gRPC / Arrow Flight SQL
                └── GizmoSQL Server (DuckDB-based)
```

## Key Files

- `GizmoSQL.pq` — Main connector source (M language section document)
- `GizmoSQL.query.pq` — Test query for Power Query SDK
- `Diagnostics.pqm` — Trace logging module
- `OdbcConstants.pqm` — ODBC constant definitions (SQL_SC, SQL_FN_CVT, etc.)
- `resources.resx` — Localized strings (button text, labels)
- `icons/` — Connector icons (16px–64px PNG)

## Build

```powershell
# Create unsigned .mez for development
$staging = New-Item -ItemType Directory -Path "staging" -Force
Copy-Item "GizmoSQL.pq","GizmoSQL.query.pq","Diagnostics.pqm","OdbcConstants.pqm","resources.resx" $staging
Copy-Item "icons\*.png" $staging
Compress-Archive -Path "staging\*" -DestinationPath "GizmoSQL.zip"
Rename-Item "GizmoSQL.zip" "GizmoSQL.mez" -Force
```

Install to: `[Documents]\Power BI Desktop\Custom Connectors\`

## Key Patterns

### Odbc.DataSource Options
The `SqlCapabilities` record declares what SQL the backend supports so Power BI generates compatible queries for query folding. Key settings:
- `SupportsTop = false` — GizmoSQL uses `LIMIT`/`OFFSET`, not `TOP`
- `LimitClauseKind = LimitClauseKind.LimitOffset`
- `Sql92Conformance = 8` — Full SQL-92
- `SupportsNumericLiterals`, `SupportsStringLiterals`, `SupportsOdbcDateLiterals`, etc. — must be `true` for DirectQuery folding

### Trace Logging
`EnableTraceOutput` (line 5 in `GizmoSQL.pq`) controls the Diagnostics module. Set to `false` for production, `true` for development. When enabled, traces appear in Power BI's Mashup Container logs at `%LOCALAPPDATA%\Microsoft\Power BI Desktop\Traces\`.

### Authentication
The connector supports three auth kinds via `Extension.CurrentCredential()`:
- `UsernamePassword` → ODBC `UID`/`PWD`/`authType=basic`
- `Key` → ODBC `token`/`authType=token`
- `Implicit` → ODBC `authType=external` (OAuth browser flow)

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
