# GizmoSQL Power BI connector — managed Native-AOT ADBC driver (alternative approach)

This folder is an **additive, self-contained alternative** to the connector on
the `adbc-flight-sql` branch. It does not modify or replace any of the branch's
files. Where the branch connector loads the **stock** `libadbc_driver_flightsql.dll`
(Apache Arrow Go driver), this approach ships a **purpose-built managed C# ADBC
driver** for GizmoSQL, compiled to a self-contained native library with
**.NET Native AOT**, plus a matching `.mez` connector.

It was built independently against a production GizmoSQL DW and works end-to-end
in Power BI Desktop. Sharing it here for comparison / possible merge.

## Why a managed driver — two findings worth your attention

1. **`tls_skip_verify` is a no-op in the stock Flight SQL driver.**
   The branch connector sets
   `adbc.flight.sql.client_option.tls_skip_verify = "true"`. Per the Apache ADBC
   docs that option is **deprecated and has no effect** (gRPC removed the
   underlying mechanism). Against a GizmoSQL server with a **self-signed cert**,
   the stock driver fails at the TLS handshake
   (`x509: certificate signed by unknown authority`; with a CA supplied,
   `x509: ... doesn't contain any IP SANs` / `relies on legacy Common Name`).
   The only fix for the stock path is to regenerate the server cert **with a
   SAN**. This managed driver instead honors a real skip-verify
   (`SslClientAuthenticationOptions.RemoteCertificateValidationCallback`), so it
   connects to a self-signed / SAN-less server exactly like the GizmoSQL GUI
   client — no cert wrangling, no server change. (Relevant to the planned
   GizmoSQL-specific Go driver noted in `CLAUDE.md`.)

2. **The Flight reader produces buffers the C Data Interface can't export.**
   `Apache.Arrow.Flight` decodes record batches into buffers backed by managed
   `ReadOnlyMemory<byte>`. `Apache.Arrow`'s `CArrowArrayExporter` cannot export
   those and throws
   `An ArrowArray of type String could not be exported: failed on buffer #1`
   the moment Power BI pulls a string column. `ArrowExportNormalizer` rebuilds
   each batch into native-buffer-backed arrays before returning it. This is a
   managed-driver-only issue (the Go stock driver isn't affected); the repro +
   fix live in `test/.../CExportReproTests.cs`.

## What's here

| Path | What |
| --- | --- |
| `src/GizmoData.Adbc.Driver.GizmoSql/` | Managed ADBC driver for GizmoSQL (Flight SQL over gRPC; password / token / OAuth; configurable TLS). Includes `ArrowExportNormalizer`. |
| `src/GizmoData.Adbc.Driver.GizmoSql.Native/` | Native-AOT shim exporting the C-ABI `GizmoSqlAdbcDriverInit` (forwards to `CAdbcDriverExporter.AdbcDriverInit(..., new GizmoSqlDriver())`). Produces `gizmosql_adbc.dll`. |
| `powerbi/` | The `.mez` connector (`GizmoSql.m` + DuckDB SQL generator + icons). Loads the managed driver via `Adbc.Connection` with `DriverType = "Unmanaged"`. |
| `scripts/publish-native.ps1` | Native-AOT publish (handles the `vswhere`-on-PATH gotcha). |
| `scripts/build-mez.ps1` | Packages `powerbi/` into `GizmoSql.mez`. |
| `bench/GizmoSqlBench/` | Throughput benchmark (rows/s, MB/s, normalize-copy %). |
| `test/` | Unit + integration tests, incl. the C-export repro. |

## Connector UX

`GizmoSql.Database(server, optional skipTlsVerification, optional options)`,
shown as **GizmoSQL (Beta)**:

- **Server** — `grpc+tls://hostname:31337`
- **Skip TLS verification** — `true` for a self-signed cert
- **Advanced Options → SQL statement** — empty for the catalog/schema/table
  navigator (Import or DirectQuery with folding), or a SQL statement to run and
  import.

## Build & install (standalone Power BI Desktop)

```pwsh
pwsh scripts/publish-native.ps1          # -> gizmosql_adbc.dll (Native AOT)
# copy gizmosql_adbc.dll (admin) to:
#   <PBI install>\bin\ADBC Drivers\GizmoSql\gizmosql_adbc.dll
pwsh scripts/build-mez.ps1 -Install      # -> GizmoSql.mez into Custom Connectors
```

Then enable *Options → Security → Data Extensions → allow any extension* (the
`.mez` is unsigned, unlike the branch's signed `.pqx`) and restart. Requires the
**standalone** (MSI) Power BI Desktop — the Microsoft Store build's
`bin\ADBC Drivers` is read-only.

## Trade-offs vs. the branch connector

| | This (managed AOT) | Branch (`adbc-flight-sql`) |
| --- | --- | --- |
| Driver | managed C#, Native-AOT `gizmosql_adbc.dll` | stock `libadbc_driver_flightsql.dll` |
| Self-signed TLS | real skip-verify, no server change | needs SAN cert (`tls_skip_verify` is a no-op) |
| Packaging | unsigned `.mez` | **signed `.pqx` + MSI installer** (no security toggle) |
| Maturity | functional, tested | CI, folding tests, installer, signing |

The branch connector is more productized (signing + installer). This approach's
value is the self-signed-cert story and the managed-driver building blocks.
Throughput is transport-bound (~20 MB/s on the test link); the driver adds
negligible overhead (the normalize copy is ~1.5% of total).
