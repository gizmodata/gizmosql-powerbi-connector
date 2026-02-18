[Version = "1.0.0"]
section GizmoSQL;

// Diagnostics module for trace logging (disable for release builds)
EnableTraceOutput = false;

// Load helper modules
Diagnostics = Extension.LoadFunction("Diagnostics"),
    Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value,
    Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result,
    Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();

ODBC = Extension.LoadFunction("OdbcConstants");

// Configuration constants
Config_DriverName = "GizmoSQL ODBC Driver";
Config_SqlConformance = ODBC[SQL_SC][SQL_SC_SQL92_FULL];
Config_LimitClauseKind = LimitClauseKind.LimitOffset;
Config_UseParameterBindings = null;
Config_StringLiteralEscapeCharacters = { "'" };
Config_UseCastInsteadOfConvert = true;
Config_EnableDirectQuery = true;

[DataSource.Kind = "GizmoSQL", Publish = "GizmoSQL.Publish"]
shared GizmoSQL.Contents = (server as text, port as number, optional database as text) as table =>
    let
        ConnectionString = [
            Driver = Config_DriverName,
            host = server,
            port = Number.ToText(port),
            useEncryption = "true"
        ],
        Credential = Extension.CurrentCredential(),
        CredentialConnectionString =
            if Credential[AuthenticationKind]? = "UsernamePassword" then
                [ UID = Credential[Username], PWD = Credential[Password], authType = "basic" ]
            else if Credential[AuthenticationKind]? = "Key" then
                [ token = Credential[Key], authType = "token" ]
            else
                error Error.Record("Error", "Unsupported authentication kind"),
        OdbcDataSource = Odbc.DataSource(ConnectionString, [
            HierarchicalNavigation = true,
            SoftNumbers = true,
            TolerateConcatOverflow = true,
            ClientConnectionPooling = true,
            CredentialConnectionString = CredentialConnectionString,
            SqlCapabilities = [
                SupportsTop = false,
                SupportsDerivedTable = true,
                Sql92Conformance = 8,
                GroupByCapabilities = 4,
                FractionalSecondsScale = 3,
                LimitClauseKind = Config_LimitClauseKind,
                StringLiteralEscapeCharacters = Config_StringLiteralEscapeCharacters
            ],
            SQLGetInfo = [
                SQL_SQL_CONFORMANCE = Config_SqlConformance,
                SQL_CONVERT_FUNCTIONS = ODBC[SQL_FN_CVT][SQL_FN_CVT_CAST],
                SQL_SQL92_PREDICATES = ODBC[SQL_SP][All],
                SQL_AGGREGATE_FUNCTIONS = ODBC[SQL_AF][All]
            ],
            HideNativeQuery = true
        ])
    in
        OdbcDataSource;

// Data source definition
GizmoSQL = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath)
        in
            { "GizmoSQL.Contents", json[server], json[port] },
    Authentication = [
        UsernamePassword = [],
        Key = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Publish to Power BI "Get Data" dialog
GizmoSQL.Publish = [
    Beta = false,
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/gizmodata/gizmosql-powerbi-connector",
    SupportsDirectQuery = Config_EnableDirectQuery,
    SourceImage = GizmoSQL.Icons,
    SourceTypeImage = GizmoSQL.Icons
];

GizmoSQL.Icons = [
    Icon16 = { Extension.Contents("GizmoSQL16.png"), Extension.Contents("GizmoSQL20.png"), Extension.Contents("GizmoSQL24.png"), Extension.Contents("GizmoSQL32.png") },
    Icon32 = { Extension.Contents("GizmoSQL32.png"), Extension.Contents("GizmoSQL40.png"), Extension.Contents("GizmoSQL48.png"), Extension.Contents("GizmoSQL64.png") }
];
