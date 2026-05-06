# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Compatibility
- Requires **GizmoSQL server `≥ v1.23.0`** for full functionality. v1.23.0 is the first server release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns`, which Power BI's `Adbc.DataSource` consumes to map columns to types. Connection, auth, and navigation work against older servers; row-data fetch fails with "Unable to understand the type for column".

### Known issues
- The seven row-data PQTest cases (Aggregation, ColumnSelection, DataTypes, Filtering, RowCount, Sorting, TopN) live in `tests-pending/` (outside the `tests/` tree PQTest scans) until a `gizmodata/gizmosql` Docker image with v1.23.0 is published. Move them back to `tests/` after the image republish — CI will pick them up automatically.

### Added
- `FLOAT` row in `TypeInfo.pqm` mirroring `REAL`. DuckDB exposes single-precision float columns under the type name `"FLOAT"` (canonical) regardless of whether they were declared `REAL` or `FLOAT`, so the connector needs both names in its lookup table.

### Fixed
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
