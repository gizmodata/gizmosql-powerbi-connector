# Pending — awaiting `gizmodata/gizmosql ≥ v1.23.0` Docker image

These PQTest queries all fetch row data and currently fail in Power BI with:

> Unable to understand the type for column

## Status

**Server fix complete (pending v1.23.0 release).** The required change in
`gizmodata/gizmosql` (`src/duckdb/duckdb_tables_schema_batch_reader.cpp`) adds
`ARROW:FLIGHT:SQL:TYPE_NAME` field metadata to `GetColumns` Flight SQL
responses, populating ADBC's `xdbc_type_name` field. Verified locally with a
freshly built `gizmosql_server` plus this connector — every standard DuckDB
type (INTEGER, VARCHAR, DOUBLE, BIGINT, SMALLINT, REAL/FLOAT, DATE, TIMESTAMP,
DECIMAL, BOOLEAN) now resolves cleanly.

These tests are parked here until a `gizmodata/gizmosql` Docker image with the
fix is published — at which point CI's `pqtest-connector` job will pick it up.

## Connector-side note

`TypeInfo.pqm` includes a `FLOAT` alias mirroring `REAL` because DuckDB exposes
`REAL` columns under the type name `"FLOAT"` (its canonical name). Don't
remove that row — it's load-bearing for any column declared `REAL` or `FLOAT`.

## Apache ADBC driver caveat (does not block these tests)

`xdbc_data_type` for DOUBLE columns reports `6` (`SQL_FLOAT`) instead of `8`
(`SQL_DOUBLE`). This is hardcoded in
`apache/arrow-adbc/go/adbc/driver/internal/shared_utils.go:719`, where both
`Float32` and `Float64` map to `XDBC_FLOAT`. With `xdbc_type_name` now
populated, Power BI's lookup-by-name finds the correct `TypeInfo.Name="DOUBLE"`
row first, so the data-type code is never consulted. Fixable upstream only.

## Tests parked here

- `Aggregation.query.pq` — `Table.Group` with `List.Sum`
- `ColumnSelection.query.pq` — `Table.SelectColumns`
- `DataTypes.query.pq` — basic INTEGER / VARCHAR / DOUBLE round-trip
- `Filtering.query.pq` — `Table.SelectRows`
- `RowCount.query.pq` — `Table.RowCount`
- `Sorting.query.pq` — `Table.Sort`
- `TopN.query.pq` — `Table.FirstN`

`Navigation.query.pq` stays in `tests/` because it only enumerates catalogs /
schemas / tables via `GetObjects` and doesn't depend on per-column type
metadata.
