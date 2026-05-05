let
    source = Adbc.Query(
        Extension.LoadFunction("FlightSqlAdbcConfig.pqm"),
        [ uri = "grpc://localhost:31337", username = "gizmosql_user", password = "gizmosql_password" ],
        "SELECT 42 AS answer"
    )
in
    source
