# GizmoSQL Power BI custom connector

`GizmoSql.mez` exposes GizmoSQL as a Power BI data source over Arrow Flight SQL.
It loads the purpose-built Native-AOT ADBC driver from this repo
(`gizmosql_adbc.dll`, built from `src/GizmoData.Adbc.Driver.GizmoSql.Native`).
That driver honors `SkipTlsVerification`, so it connects to a GizmoSQL server
with a self-signed certificate with no cert wrangling — exactly like the
GizmoSQL GUI client.

## Function

`GizmoSql.Database(server, optional skipTlsVerification, optional options)` —
shows in Get Data as **GizmoSQL (Beta)**.

- **Server** (required): the Flight SQL URI, e.g. `grpc+tls://hostname:31337`.
- **Skip TLS verification** (optional): `true` for a self-signed certificate.
- **Advanced Options → SQL statement** (`options[SqlStatement]`): leave empty
  for the catalog → schema → table navigator (Import or DirectQuery with query
  folding), or enter a SQL statement to run it and import the result.

## Install (standalone Power BI Desktop)

The native driver must live under the Power BI **install** directory, which is
writable on the standalone (MSI) install but NOT on the Microsoft Store build.

1. Build the driver: `pwsh scripts/publish-native.ps1`.
2. Copy it (admin): `gizmosql_adbc.dll` →
   `C:\Program Files\Microsoft Power BI Desktop\bin\ADBC Drivers\GizmoSql\`.
3. Build + install the connector: `pwsh scripts/build-mez.ps1 -Install`
   (drops `GizmoSql.mez` in `Documents\Power BI Desktop\Custom Connectors`).
4. Power BI Desktop → *File → Options → Security → Data Extensions* →
   "(Not Recommended) Allow any extension to load without validation" → restart.

## Using it

Get Data → **GizmoSQL (Beta)** → enter the server (e.g.
`grpc+tls://hostname:31337`), set **Skip TLS verification** = true for a
self-signed cert, and authenticate with **Basic** (username/password). Expand
**Advanced Options** to type a SQL statement, or leave it empty to browse the
navigator. The first connection prompts for credentials and reuses them for
that server afterward.

## Files

- `GizmoSql.m` — connector section document (packaged into the `.mez` as
  `GizmoSql.pq`).
- `SqlGenerator.pqm`, `SqlGeneratorCommon.pqm` — DuckDB SQL dialect generator
  for query folding (vendored from CurtHagenlocher/quack-net, Apache-2.0).
- `resources.resx` — UI strings.
- `GizmoSql.mez` — packaged connector. Rebuild with `scripts/build-mez.ps1`.
