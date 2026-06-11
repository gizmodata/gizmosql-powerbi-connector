# `Adbc.DataSource`: DirectQuery cross-table fold fails with "different data sources" despite `Value.Equals` returning `true` for identical Source bindings

> **Status (2026-06-11):** addressed on this branch by reworking the connector onto the newer experimental `Adbc.Connection` + `SqlView.Generator` APIs, whose unique-identifier argument carries the data-source identity explicitly (per @mattmasson's guidance on the upstream issue). This document is kept as the record of the `Adbc.DataSource` behavior, which remains unfixed upstream.

## TL;DR

In a Power Query M custom connector that wraps `Adbc.DataSource(...)`, two table expressions that each begin with their own `Source = MyConnector.Contents(...)` call (with byte-identical arguments) — exactly the M code shape that Power BI Desktop generates when a user picks two tables from the navigator into a DirectQuery model — fail to fold any cross-table join with:

```
Microsoft.Mashup.Engine1.Runtime.FoldingFailureException
   at Microsoft.Mashup.Engine1.Library.SqlView.SqlViewQueryDomain
       .SqlViewOptimizingQueryVisitor.VisitJoinCore(JoinQuery joinQuery)
ErrorMessage: "The left and right queries come from different data sources."
```

The optimizer's source-identity check is provably stricter than M language equality:

```m
Value.Equals(MyConnector.Contents("host", port), MyConnector.Contents("host", port))
// → true
```

So `Value.Equals` says they're the same value, but `VisitJoinCore` rejects the fold. **The optimizer is not honoring M-language equality semantics for `Adbc.DataSource` results.**

End-user symptom: "QueryUserError" / "We couldn't fold the expression to the data source. Please try a simpler expression." in DirectQuery; the same join works in Import mode (since Import doesn't require folding to a single source).

## Reproduction

Standalone, sub-second, deterministic. Uses Microsoft's own PQTest framework. No Power BI Desktop required.

### 1. Test connector

A minimal connector wrapping `Adbc.DataSource` with the Apache Arrow FlightSQL Go driver against any FlightSQL-speaking server (we used GizmoSQL — DuckDB-backed Apache Arrow Flight SQL server — but Spice.ai, Dremio, or any FlightSQL endpoint reproduces the same outcome). Connector source: `https://github.com/gizmodata/gizmosql-powerbi-connector/tree/adbc-flight-sql`.

### 2. PQTest setup

```powershell
# Get PQTest from the official NuGet package
Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.PowerQuery.SdkTools" -OutFile sdktools.zip
Expand-Archive sdktools.zip -DestinationPath sdktools -Force
$pqtest = (Get-ChildItem sdktools -Filter "PQTest.exe" -Recurse | Select -First 1).FullName

# Set credentials for the connector
@'
{
  "AuthenticationKind": "UsernamePassword",
  "AuthenticationProperties": { "Username": "joe", "Password": "joe" },
  "PrivacySetting": "None",
  "Permissions": []
}
'@ | & $pqtest set-credential -e GizmoSQL.mez -q probe.pq
```

### 3. Test queries

**`Equality.query.pq`** — proves M considers them equal:

```m
let
    SourceA = GizmoSQL.Contents("localhost", 31337, false),
    SourceB = GizmoSQL.Contents("localhost", 31337, false),
    equal = Value.Equals(SourceA, SourceB)
in
    [ Value_Equals = equal ]
// Output: Value_Equals = true
```

**`Join_OneSource.query.pq`** — control: ONE Source binding, both tables navigate from it. **Folds successfully**, returns rows:

```m
let
    Source = GizmoSQL.Contents("localhost", 31337, false),
    lineitem_Table = Source{[Name="memory",Kind="Database"]}[Data]{[Name="main",Kind="Schema"]}[Data]{[Name="lineitem",Kind="Table"]}[Data],
    orders_Table   = Source{[Name="memory",Kind="Database"]}[Data]{[Name="main",Kind="Schema"]}[Data]{[Name="orders",  Kind="Table"]}[Data],
    joined = Table.Join(lineitem_Table, {"l_orderkey"}, orders_Table, {"o_orderkey"}, JoinKind.LeftOuter, null),
    selected = Table.SelectColumns(joined, {"l_orderkey","l_extendedprice","o_orderstatus"}),
    first5 = Table.FirstN(selected, 5)
in
    first5
```

**`Join_TwoSources.query.pq`** — the actual failure shape that PBI Desktop generates from a DirectQuery model with two tables and a relationship: TWO Source bindings:

```m
let
    SourceA = GizmoSQL.Contents("localhost", 31337, false),
    lineitem_Table = SourceA{[Name="memory",Kind="Database"]}[Data]{[Name="main",Kind="Schema"]}[Data]{[Name="lineitem",Kind="Table"]}[Data],

    SourceB = GizmoSQL.Contents("localhost", 31337, false),
    orders_Table = SourceB{[Name="memory",Kind="Database"]}[Data]{[Name="main",Kind="Schema"]}[Data]{[Name="orders",Kind="Table"]}[Data],

    joined = Table.Join(lineitem_Table, {"l_orderkey"}, orders_Table, {"o_orderkey"}, JoinKind.LeftOuter, null),
    selected = Table.SelectColumns(joined, {"l_orderkey","l_extendedprice","o_orderstatus"}),
    first5 = Table.FirstN(selected, 5)
in
    first5
```

### 4. Run

```powershell
& $pqtest run-test -e GizmoSQL.mez -q Equality.query.pq -p
# {"Value_Equals":true}                                    ← M says equal

& $pqtest run-test -e GizmoSQL.mez -q Join_OneSource.query.pq -foff -p
# Status: Passed, RowCount: 5                              ← strict-fold mode works

& $pqtest run-test -e GizmoSQL.mez -q Join_TwoSources.query.pq -foff -p
# Status: Failed
# Error: "We couldn't fold the expression to the data source.
#         Please try a simpler expression."
# Microsoft.Data.Mashup.ErrorCode: 10704                   ← FAILURE
```

`-foff` (`--failOnFoldingFailure`, documented as *"Force query failure when it doesn't completely fold (Direct Query behavior)"*) is what triggers the same fold-failure path Power BI Desktop's DirectQuery model evaluation hits.

### 5. Mashup engine trace excerpt

`-l Engine` traces from PQTest produce identical stack to Power BI Desktop's mashup container:

```
Engine/IO/Adbc/Connection/Open    ResourcePath: {"server":"localhost","port":31337}
                                  DriverName: ADBC Flight SQL Driver - Go
                                  DriverVersion: (unknown or development build)
                                  DBMSName: gizmosql
                                  DBMSVersion: duckdb v1.5.2
                                  Pooling: False
[...repeated 5×, identical metadata each time, fresh connection each navigation step...]

SqlViewQueryDomain/ReportFoldingFailure
   Exception: Microsoft.Mashup.Engine1.Runtime.FoldingFailureException
       at SqlViewOptimizingQueryVisitor.VisitJoinCore(JoinQuery joinQuery)
       at SqlViewOptimizingQueryVisitor.VisitJoin(JoinQuery joinQuery)
   ErrorMessage: "The left and right queries come from different data sources."
```

Every connection-level open shows **byte-identical `ResourcePath`, `DriverName`, `DriverVersion`, `DBMSName`, `DBMSVersion`** for both Source bindings.

### 6. Independent driver-side validation

Probing the same Apache Go FlightSQL driver DLL (`libadbc_driver_flightsql.dll` from `apache/arrow-adbc` release `apache-arrow-adbc-23`, version 1.11.0) directly via the Python `adbc-driver-flightsql` wheel against the same live server confirms `GetInfo` results are byte-identical across two independent `AdbcDatabase`/`AdbcConnection` opens with identical args:

```
=== Byte-for-byte equality across 2 independent connections ===
IDENTICAL across all 7 info codes.
  VENDOR_NAME           = 'gizmosql'
  VENDOR_VERSION        = 'duckdb v1.5.2'
  VENDOR_ARROW_VERSION  = '23.0.1'
  DRIVER_NAME           = 'ADBC Flight SQL Driver - Go'
  DRIVER_VERSION        = 'v1.11.0'
  DRIVER_ARROW_VERSION  = 'v18.5.2'
  DRIVER_ADBC_VERSION   = 1001000
```

(Note one inconsistency: the same DLL reports `DriverVersion: (unknown or development build)` to PBI's mashup container but `'v1.11.0'` via the Python ADBC bindings. PBI's wrapper is reading the version differently than Apache's reference clients do. Probably not causal here — every per-connection open trace shows the same string — but worth flagging.)

## What we ruled out

| Hypothesis | Test | Result |
|---|---|---|
| Connector M wrapping is opaque (`Diagnostics.LogValue2` etc.) | Stripped all wrappers, direct `Adbc.DataSource(...)` call | ❌ no change |
| `Adbc.connection.catalog`/`db_schema = true` confuses PBI | Set both to `false` (matches Spice's working-config recipe) | ❌ no change |
| Missing `NativeQueryProperties.EnableFolding = true` | Added | ❌ no change |
| Wrong `navigationSteps` shape | Replaced `{[]}` placeholder with full 3-level Catalog→Schema→Table descriptor | ❌ no change |
| Inline lambda in `Value.ReplaceType` (vs named function) | Refactored to named `GizmoSqlConnectionImpl` (matches Spice's named `SpiceConnectionImpl`) | ❌ no change |
| `Extension.CurrentCredential()` is non-deterministic | Hardcoded credentials in M | ❌ no change |
| Result needs explicit `Value.ReplaceMetadata([DataSource.Kind=..., DataSource.Path=...])` | Added | ❌ no change |
| Stale PBI Desktop caches | Cleared `Cache`, `ExtensionCache`, `FoldedArtifactsCache`, `LuciaCache`, fresh PBIX | ❌ no change |
| Stale model state in saved PBIX | Tested with brand-new blank PBIX | ❌ no change |
| Server-side metadata varies per connection | Inspected `gizmosql/duckdb_sql_info.cpp:200-206`: all `FLIGHT_SQL_SERVER_*` strings are compile-time constants | ❌ deterministic |
| Driver-side metadata varies per call | Reviewed `apache/arrow-adbc/go/adbc/driver/flightsql/flightsql_driver.go:69` + `driver_info.go`: all defaults are constants | ❌ deterministic |

## What we believe is wrong

The mashup engine's data-source-identity check inside `Microsoft.Mashup.Engine1.Library.SqlView.SqlViewQueryDomain.SqlViewOptimizingQueryVisitor.VisitJoinCore` is using stricter-than-`Value.Equals` equality on the values returned by `Adbc.DataSource`. We believe the check is comparing wrapped CLR-object identity (per-call) rather than configuration-value equality (which would correctly hash-equate two calls with byte-identical arguments).

`Odbc.DataSource` does not exhibit this — the v1.x ODBC version of this same connector (against the same backend) folds cross-table joins in DirectQuery without issue. Microsoft's *certified* ADBC connectors (Databricks, Snowflake, Dremio, BigQuery, Impala) also fold cross-table joins in DirectQuery. So either:

- those certified connectors ship through a private partner channel that opts into different optimizer behavior, **or**
- their backing ADBC drivers expose a piece of metadata that Apache's Go FlightSQL driver doesn't.

Either way, the recipe Apache + Spice + this connector are following — which is the only public ADBC custom-connector recipe — produces non-foldable cross-table joins in DirectQuery.

## Related public reports

- **[spiceai/powerbi-connector#10](https://github.com/spiceai/powerbi-connector/issues/10)** — *"Adding Table Relationships causes 'We couldn't fold the expression to the data source.' error"*. Independent reproduction on a different ADBC backend (Spice.ai instead of GizmoSQL). **Open, no maintainer response, no workaround.**
- **[mariadb-corporation/mariadb-powerbi#12](https://github.com/mariadb-corporation/mariadb-powerbi/issues/12)** — Same fold-failure error on a different (non-ADBC) custom connector. Closed without resolution.
- **[Microsoft Fabric: ADBC LEFT JOIN UnknownError](https://community.fabric.microsoft.com/t5/Power-Query/DataSource-Error-ADBC-UnknownError-while-running-a-query-with/m-p/4806424)** — different ADBC error path. Community consensus: *"the new ADBC implementation provides extremely poor messaging compared to previous versions."*
- **[Microsoft Fabric: Table.Join + DirectQuery](https://community.fabric.microsoft.com/t5/Power-Query/Table-Join-does-it-works-with-DirectQuery-or-not/td-p/2082526)** — Microsoft Community Support confirms the design rule: *"tables must originate from the same SQL database for `Table.Join` to function properly in DirectQuery mode"*. The "different data sources" check is intentional; the bug is that it's mistakenly identifying same-source as different-source for `Adbc.DataSource`.

## Environment

- Power BI Desktop: 2.153.777.0 (26.04 / April 2026)
- Connector: `gizmodata/gizmosql-powerbi-connector` `adbc-flight-sql` branch
- ADBC FlightSQL driver: `apache/arrow-adbc` release `apache-arrow-adbc-23` (driver version 1.11.0, Go-built)
- Backend: GizmoSQL `v1.24.0` (DuckDB `v1.5.2`)
- PQTest: `Microsoft.PowerQuery.SdkTools` (latest from NuGet)

## What would help

1. **Documentation** of what Power BI's mashup-engine optimizer uses for the `Adbc.DataSource` source-identity check, so connector authors can align with it.
2. **Either**: change the check to honor `Value.Equals` semantics (treat two `Adbc.DataSource(driver, conn, opts)` calls with structurally-equal args as the same source), **or** expose a connector-level mechanism to declare "two calls with these args produce the same data source" — analogous to whatever the certified-partner connectors are using.
3. **A standardized, public way for ADBC custom connectors to participate in DirectQuery cross-table folding**, since the closed-source path used by certified Microsoft partners is the only one that currently works.
