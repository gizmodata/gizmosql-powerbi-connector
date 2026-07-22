# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v2.0.1] - 2026-07-22

### Fixed
- **MSI installer artwork no longer squished.** The CI step that renders the WixUI banner/dialog bitmaps drew the square 1024x1024 GizmoSQL logo into hardcoded 4:1 boxes, distorting it. The logo is now scaled aspect-ratio-correct: small on the right of the 493x58 banner (clear of the left-aligned page title) and in the left strip of the 493x312 dialog (clear of the text column starting ~x=165).
- **MSI upgrade hardening.** `MajorUpgrade` now sets `AllowSameVersionUpgrades="yes"` so reinstalling the same version replaces files instead of installing side-by-side, and the CI MSI build fails fast if a semantic version cannot be derived from the release tag (previously it silently fell back to `0.0.0`, which would break upgrade ordering).

## [v2.0.0] - 2026-06-11

**BREAKING:** v2.0 replaces the ODBC backend with ADBC over Arrow Flight SQL. Data flows column-natively in Apache Arrow format from server to Power BI — no row/column conversions in the driver path. You must install the Apache Flight SQL ADBC driver (bundled by the MSI installer), and the GizmoSQL ODBC driver is no longer used.

### Compatibility
- Requires **GizmoSQL server `≥ v1.23.0`**. v1.23.0 is the first server release that emits `ARROW:FLIGHT:SQL:TYPE_NAME` field metadata on `GetColumns`, which the connector maps to Power BI column types. Connection, auth, and navigation work against older servers; row-data fetch fails with "Unable to understand the type for column".
- Requires a **recent Power BI Desktop build** for the `Adbc.Connection` / `SqlView.Generator` extensibility functions. These M APIs are experimental per Microsoft and may change across Power BI Desktop releases.

### Changed
- **Replaced the ODBC backend with ADBC over Arrow Flight SQL.** The connector drives the Apache `libadbc_driver_flightsql.dll` through Power BI's `Adbc.Connection` + `SqlView.Generator` extensibility APIs, eliminating the GizmoSQL ODBC driver dependency.
- **DirectQuery cross-table joins fold.** `SqlView.Generator`'s first argument is a unique identifier the mashup engine uses to decide whether two queries target the same data source; the connector keys it on the connection target (URI + default catalog — never credentials), so all tables from one connection share one identity and joins fold into a single native query. This resolves the blocker tracked in [#2](https://github.com/gizmodata/gizmosql-powerbi-connector/issues/2) / [microsoft/vscode-powerquery-sdk#409](https://github.com/microsoft/vscode-powerquery-sdk/issues/409), where the documented `Adbc.DataSource` recipe rejected such joins with `FoldingFailureException` "different data sources" at `VisitJoinCore`. `BUG_REPORT_ADBC_DIRECTQUERY_FOLD.md` documents the original issue. Initial architecture contributed in [PR #3](https://github.com/gizmodata/gizmosql-powerbi-connector/pull/3) by @flozer, adapted to the stock Apache Flight SQL ADBC (Go) driver.
- **Hierarchical navigator** built by the connector from `information_schema` / `pragma_table_info` queries, with foldable navigation steps and primary-key detection.
- **DuckDB-tuned SQL generator** (`SqlGenerator.pqm` / `SqlGeneratorCommon.pqm`), vendored from [CurtHagenlocher/quack-net](https://github.com/CurtHagenlocher/quack-net) (Apache-2.0) with `Text.*` predicate folds carried over from the earlier spiceai/powerbi-connector lineage (MIT). Folds Power BI transformations to DuckDB-native SQL — `date_trunc`, `date_diff`, the `to_<unit>(n)` interval family, `epoch_us`, `make_time`, `instr`, `substring + concat`, `CAST(... AS VARCHAR)`, `Number.RoundUp`/`RoundDown`, and a null-aware `List.Contains` → `IN (...)`; the type table covers `HUGEINT`, `UUID`, `JSON`, `BLOB`, and `TIMESTAMP WITH TIME ZONE`.
- **Use Encryption (TLS)** now selects between `grpc+tls://` and `grpc://` URI schemes instead of an ODBC connection-string flag.

### Added
- **Authentication:** username/password (Basic), bearer token (Key), and OAuth browser SSO (GizmoSQL Enterprise). OAuth is implemented entirely in M against the server's `/oauth/initiate` + poll flow: the IdP's ID token is presented through the Flight **handshake** (`username = "token"`, JWT as password — the JDBC / gizmosql-ui convention), so the server verifies it via JWKS and issues its own session JWT — no custom driver needed. Assumes the default `--oauth-port` `31339`; the OAuth endpoint's TLS certificate must be trusted by the client (`Web.Contents` cannot skip verification), and an expired JWT requires interactive re-auth (no refresh token).
- **MSI installer** bundles `libadbc_driver_flightsql.dll` from `apache/arrow-adbc` release `apache-arrow-adbc-23` (driver version 1.11.0), installs it on the system `PATH`, drops the signed connector, and registers the signing certificate as trusted — no Power BI security downgrade required.
- **CI** builds and PQTests the connector against a live GizmoSQL server on every push and PR (to `main` and `adbc-flight-sql`), and signs + releases on `v*` tags. GitHub Release notes embed the curated `CHANGELOG.md` section.
- **Debug tooling** in `Diagnostics.pqm` (off by default): `IsEnabled` (marker-file check at `C:\Users\Public\gizmosql_pbi_debug.flag`) and `MaskCredentials` for redacting `password` / `Authorization` from traces; documented in the README *Debug logging* section.

### Removed
- **The GizmoSQL ODBC driver dependency** and its Windows registry registration. The MSI no longer ships the ODBC DLL or the VC++ runtime — the Apache Flight SQL ADBC driver is a Go-built binary with no MSVCRT dependency. `OdbcConstants.pqm` is gone.

### Known limitations
- **Foreign-key relationships are not auto-created.** Automatic FK import is a built-in of Power BI's native `Odbc.DataSource` handler (it reads the driver's `SQLForeignKeys`); Power Query exposes no API for a hand-rolled ADBC navigator to declare relationships, and the only documented workaround (`Table.NestedJoin`) does not survive the `SqlView.Generator` layer. The connector declares each table's primary key, so Power BI's built-in **Autodetect** finds relationships reliably on same-named keys (e.g. `emp.dept_id` → `dept.dept_id`). See the README *Relationships* section.

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
