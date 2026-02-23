let
    source = Odbc.Query("Driver=GizmoSQL ODBC Driver;host=localhost;port=31337;uid=gizmosql_user;pwd=gizmosql_password;useEncryption=false", "SELECT 42 AS answer")
in
    source
