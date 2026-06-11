# GizmoData.Adbc.Driver.GizmoSql

A C# ADBC (Arrow Database Connectivity) driver for [GizmoSQL](https://github.com/gizmodata/gizmosql), enabling Power BI integration via the Arrow Flight SQL protocol.

## Features

- Full ADBC interface implementation for GizmoSQL
- Arrow Flight SQL protocol over gRPC
- Password, token, and OAuth/SSO browser authentication
- TLS support with configurable certificate verification
- Power BI Navigator metadata (catalogs, schemas, tables, columns)

## Quick Start

```csharp
using Apache.Arrow.Adbc;
using GizmoData.Adbc.Driver.GizmoSql;

var driver = new GizmoSqlDriver();
var parameters = new Dictionary<string, string>
{
    [GizmoSqlParameters.ServerAddress] = "grpc+tls://localhost:31337",
    [GizmoSqlParameters.Username] = "user",
    [GizmoSqlParameters.Password] = "pass",
};

using var database = driver.Open(parameters);
using var connection = database.Connect(null);
using var statement = connection.CreateStatement();

statement.SqlQuery = "SELECT * FROM my_table";
var result = statement.ExecuteQuery();
```

## Connection Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adbc.gizmosql.server_address` | Full URI (e.g. `grpc+tls://host:port`) | — |
| `adbc.gizmosql.host` | Hostname (alternative to full URI) | — |
| `adbc.gizmosql.port` | Port number | `31337` |
| `adbc.gizmosql.username` | Username | — |
| `adbc.gizmosql.password` | Password | — |
| `adbc.gizmosql.tls.enabled` | Enable TLS | `true` |
| `adbc.gizmosql.tls.skip_verify` | Skip TLS cert verification | `false` |
| `adbc.gizmosql.auth.type` | Auth type: `password`, `token`, `external` | `password` |
| `adbc.gizmosql.auth.token` | JWT token (for token auth) | — |
| `adbc.gizmosql.oauth.port` | OAuth server port | `31339` |
| `adbc.gizmosql.oauth.url` | Explicit OAuth base URL | — |
| `adbc.gizmosql.oauth.timeout` | OAuth timeout in seconds | `300` |
