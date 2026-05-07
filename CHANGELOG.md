# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- `BUG_REPORT_ADBC_DIRECTQUERY_FOLD.md` documenting the upstream Microsoft Power BI bug that prevents cross-table query folding in DirectQuery for ADBC-based custom connectors. Filed as [microsoft/vscode-powerquery-sdk#409](https://github.com/microsoft/vscode-powerquery-sdk/issues/409). Symptom: `FoldingFailureException` at `SqlViewOptimizingQueryVisitor.VisitJoinCore` ("different data sources") when two tables in the same DirectQuery model navigate from separate `Source = GizmoSQL.Contents(...)` bindings — even though `Value.Equals` returns `true` between those bindings. Same root cause as [spiceai/powerbi-connector#10](https://github.com/spiceai/powerbi-connector/issues/10). Import mode is unaffected. v1.x ODBC (which uses `Odbc.DataSource` rather than `Adbc.DataSource`) is unaffected.

### Changed
- Align ADBC connector configuration with the documented Spice.ai recipe: set `adbc.connection.catalog = false` in `FlightSqlAdbcConfig.SupportedConnectionOptions` (previously `true`), add `NativeQueryProperties` (with `EnableFolding = true`) to `GizmoSQL.Publish`, and refactor the connector function to a named identifier (`GizmoSqlConnectionImpl`) rather than an inline lambda. None of these changes individually fixes the cross-table fold bug above, but they bring this connector to the recipe other public ADBC FlightSQL connectors converge on.

### Added (debug instrumentation)
- Investigation tooling for surfacing ADBC connector failures inside Power BI Desktop. Off by default; intended for development.
  - `Diagnostics.pqm` — `IsEnabled` (marker-file check at `C:\Users\Public\gizmosql_pbi_debug.flag`) and `MaskCredentials` helper for redacting `password` / `Authorization` fields out of trace records.
  - `SqlGenerator.pqm` — `WrapOverrideHandler` infrastructure that wraps every AstVisitor override (`FunctionOverrides`, `BinaryOperatorOverrides`, `UnaryOperatorOverrides`) with rich error reporting (handler name + AST `Kind` + inner exception) when `DebugEnabled = true`. Re-raised as a `GizmoSQL.FoldError` so the Power BI error dialog shows the failing override directly. Also writes `[GizmoSQL.PBI/Override:<name>] FAILED on Kind=<...>` trace entries.
  - `README.md` — *Debug logging* section with the full development workflow: how to enable PBI Desktop tracing, where the trace files live, and the grep patterns for filtering out `[GizmoSQL.PBI/...]` entries.

## [v2.0.0] - 2026-05-06

### Compatibility
- Requires **GizmoSQL server `≥ v1.23.0`** for full functionality. v1.23.0 is the first server release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns`, which Power BI's `Adbc.DataSource` consumes to map columns to types. Connection, auth, and navigation work against older servers; row-data fetch fails with "Unable to understand the type for column".

### Added
- `FLOAT` row in `TypeInfo.pqm` mirroring `REAL`. DuckDB exposes single-precision float columns under the type name `"FLOAT"` (canonical) regardless of whether they were declared `REAL` or `FLOAT`, so the connector needs both names in its lookup table.
- GitHub Release notes now embed the curated `CHANGELOG.md` section for the tag at the top, with the auto-generated PR/commit list appended below — keeps `CHANGELOG.md` as the single source of truth for release notes (CI workflow change).
- `README.md` rewritten to describe the v2.x ADBC architecture (Apache Flight SQL ADBC driver, `libadbc_driver_flightsql.dll`, DuckDB-native SQL generator) instead of the v1.x ODBC story.

### Fixed
- Drop the "Beta" badge in the Power BI "Get Data" dialog. `GizmoSQL.Publish.Beta` was flipped to `true` during the v1→v2 rewrite as a precaution; v2.0.0 testing has been clean against `gizmodata/gizmosql ≥ v1.23.0`, so it's back to `false` to match the v1.x behavior.
- Pass `CredentialConnectionString` to `Adbc.DataSource` as a record (let-block) instead of a function value, so `username`/`password` actually reach the underlying ADBC driver. Without this, the Apache Flight SQL ADBC driver sent no Authorization header and GizmoSQL rejected metadata calls with "Invalid Authorization Header type! (Unknown; GetObjects(GetCatalogs))".
- Rewrite `SqlGenerator.pqm` to emit DuckDB-native SQL instead of DataFusion-flavored idioms inherited from spiceai/powerbi-connector. Without this fix, query folding for date/time math, `Text.PositionOf`, `Text.RemoveRange`, and `Logical.From(text)` would emit SQL that DuckDB rejects (e.g. `timestampadd`, `timestampdiff`, `TO_TIMESTAMP('string')`, `INSERT(s,p,n,r)`, `TO_VARCHAR`, 3-arg `POSITION`). Replaced with: `date_trunc`, `date_diff`, the `to_<unit>(n)` interval-builder family, `epoch_us`, `make_time`, `microsecond`, `instr`, `substring + concat`, and `CAST(... AS VARCHAR)`. Added a small `DuckDb.*` AST adapter block in `SqlGenerator.pqm` to keep the per-override changes localized.
- Added `tests/duckdb-folding.sql` to verify the SQL idioms each rewritten override emits parse and evaluate correctly against DuckDB.

### Changed
- **BREAKING:** Replaced ODBC backend with ADBC (Arrow Database Connectivity) over Arrow Flight SQL. The connector now calls `Adbc.DataSource` directly with the Apache `libadbc_driver_flightsql.dll`, eliminating the GizmoSQL ODBC driver dependency. Data flows column-natively in Apache Arrow format from server to Power BI — no row/column conversions in the driver path.
- Bumped connector version to `2.0.0` to reflect the backend change.
- Replaced `OdbcConstants.pqm` with `SqlGenerator.pqm`, `SqlGeneratorCommon.pqm`, `TypeInfo.pqm`, and `FlightSqlAdbcConfig.pqm` (adapted from spiceai/powerbi-connector under MIT license).
- `Use Encryption (TLS)` now selects between `grpc+tls://` and `grpc://` URI schemes instead of an ODBC connection string flag.

### Added
- MSI installer now bundles `libadbc_driver_flightsql.dll` from `apache/arrow-adbc` release `apache-arrow-adbc-23` (driver version 1.11.0). Installed to `Program Files\GizmoSQL Power BI Connector\` and added to system `PATH` so the Power BI mashup container can resolve it by name.

### Removed
- Dependency on the GizmoSQL ODBC driver and its Windows registry registration. The MSI no longer ships the ODBC DLL or VC++ runtime — the Apache Flight SQL ADBC driver is a Go-built binary with no MSVCRT dependency.
- OAuth (browser-flow SSO) authentication. The v1.x ODBC driver implemented the `/oauth/initiate` + poll dance internally; the generic Apache Flight SQL ADBC driver has no equivalent hook. OAuth will return once a GizmoSQL-specific Go ADBC driver (vendoring `apache/arrow-adbc/go/adbc/driver/flightsql` and adding the external-auth flow) is available.

## [v1.1.2] - 2026-03-02

### Changed
- Pin GizmoSQL ODBC driver to v1.1.2 (adds auto-commit support)

## [v1.1.1] - 2026-03-02

### Fixed
- Document the OAuth (Browser) authentication method in README, which was supported since v1.0.0 but missing from the docs.

### Added
- Add optional `Default Catalog` field to the "Get Data" dialog, allowing users to specify which database/catalog to use at connection time.
- MSI installer now registers the signing certificate thumbprint as a Power BI trusted third-party connector, eliminating the security warning at the default "Recommended" security level.

### Changed
- Enable hierarchical navigation (`HierarchicalNavigation = true`) so the Navigator pane shows a drill-down tree of catalog > schema > table instead of a flat list.
- Pin GizmoSQL ODBC driver to v1.1.0 in CI and MSI installer builds instead of using latest release.

## [v1.1.0] - 2026-02-25

### Fixed
- Fix Power BI DirectQuery "UNSEARCHABLE" query folding failure by adding `SupportsNumericLiterals`, `SupportsStringLiterals`, `SupportsOdbcDateLiterals`, `SupportsOdbcTimeLiterals`, and `SupportsOdbcTimestampLiterals` to `SqlCapabilities` in `Odbc.DataSource` options.

### Changed
- Disable `EnableTraceOutput` (Diagnostics module trace logging) by default. Set to `true` in `GizmoSQL.pq` to re-enable for development.

## [v1.0.0] - 2026-02-24

Initial release.

- Power Query custom connector wrapping the GizmoSQL ODBC driver
- DirectQuery and Import mode support
- Query folding with `LIMIT`/`OFFSET`, `CAST`, SQL-92, derived tables, and all standard aggregate functions
- Username/password, token, and OAuth (browser) authentication
- Navigator pane with catalog > schema > table browsing
- Signed `.pqx` for Power BI's default "Recommended" security setting
