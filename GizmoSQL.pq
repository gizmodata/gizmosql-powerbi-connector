[Version = "1.0.0"]
section GizmoSQL;

// Diagnostics module for trace logging (disable for release builds)
EnableTraceOutput = false;

// Helper to load .pqm modules from within the extension package
Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

// Load helper modules
Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value;
Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result;
Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();

ODBC = Extension.LoadFunction("OdbcConstants.pqm");

// Configuration constants
Config_DriverName = "GizmoSQL ODBC Driver";
Config_SqlConformance = ODBC[SQL_SC][SQL_SC_SQL92_FULL];
Config_LimitClauseKind = LimitClauseKind.LimitOffset;
// Parameter bindings are auto-detected via SQLGetFunctions(SQL_API_SQLBINDPARAMETER) probe.
// Odbc.DataSource does not accept UseParameterBindings as an option directly.
Config_StringLiteralEscapeCharacters = { "'" };
Config_UseCastInsteadOfConvert = true;
Config_EnableDirectQuery = true;

// Function type with UI metadata for Power BI "Get Data" dialog
GizmoSQL.ContentsType = type function (
    server as (type text meta [
        Documentation.FieldCaption = "Server",
        Documentation.FieldDescription = "Hostname or IP address of the GizmoSQL server",
        Documentation.SampleValues = {"localhost"}
    ]),
    port as (type number meta [
        Documentation.FieldCaption = "Port",
        Documentation.FieldDescription = "Port number of the GizmoSQL server",
        Documentation.SampleValues = {31337}
    ]),
    optional useEncryption as (type logical meta [
        Documentation.FieldCaption = "Use Encryption (TLS)",
        Documentation.FieldDescription = "Enable TLS encryption for the connection",
        Documentation.AllowedValues = {true, false}
    ]),
    optional disableCertificateVerification as (type logical meta [
        Documentation.FieldCaption = "Disable Certificate Verification",
        Documentation.FieldDescription = "Skip TLS certificate verification (not recommended for production)",
        Documentation.AllowedValues = {true, false}
    ])
) as table;

[DataSource.Kind = "GizmoSQL", Publish = "GizmoSQL.Publish"]
shared GizmoSQL.Contents = Value.ReplaceType((server as text, port as number, optional useEncryption as logical, optional disableCertificateVerification as logical) as table =>
    let
        ConnectionString = [
            Driver = Config_DriverName,
            host = server,
            port = Number.ToText(port),
            useEncryption = if useEncryption <> false then "true" else "false",
            disableCertificateVerification = if disableCertificateVerification = true then "true" else "false"
        ],
        Credential = Extension.CurrentCredential(),
        CredentialConnectionString =
            if Credential[AuthenticationKind]? = "UsernamePassword" then
                [ UID = Credential[Username], PWD = Credential[Password], authType = "basic" ]
            else if Credential[AuthenticationKind]? = "Key" then
                [ token = Credential[Key], authType = "token" ]
            else if Credential[AuthenticationKind]? = "Implicit" then
                [ authType = "external" ]
            else
                error Error.Record("Error", "Unsupported authentication kind"),
        OdbcDataSource = Odbc.DataSource(ConnectionString, [
            HierarchicalNavigation = false,
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
                StringLiteralEscapeCharacters = Config_StringLiteralEscapeCharacters,
                SupportsOdbcDateLiterals = true,
                SupportsOdbcTimeLiterals = true,
                SupportsOdbcTimestampLiterals = true
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
        OdbcDataSource, GizmoSQL.ContentsType);

// Data source definition
GizmoSQL = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath)
        in
            { "GizmoSQL.Contents", json[server], json[port], json[useEncryption]?, json[disableCertificateVerification]? },
    Authentication = [
        UsernamePassword = [],
        Key = [],
        Implicit = [Label = "OAuth (Browser)"]
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
