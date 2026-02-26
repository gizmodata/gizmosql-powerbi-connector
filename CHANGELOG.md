# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Add optional `Default Catalog` field to the "Get Data" dialog, allowing users to specify which database/catalog to use at connection time.
- MSI installer now registers the signing certificate thumbprint as a Power BI trusted third-party connector, eliminating the security warning at the default "Recommended" security level.

### Changed
- Enable hierarchical navigation (`HierarchicalNavigation = true`) so the Navigator pane shows a drill-down tree of catalog > schema > table instead of a flat list.

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
