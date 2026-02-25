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
                SupportsNumericLiterals = true,
                SupportsStringLiterals = true,
                SupportsOdbcDateLiterals = true,
                SupportsOdbcTimeLiterals = true,
                SupportsOdbcTimestampLiterals = true
            ],
            SQLGetInfo = [
                SQL_SQL_CONFORMANCE = Config_SqlConformance,
                SQL_CONVERT_FUNCTIONS = ODBC[SQL_FN_CVT][SQL_FN_CVT_CAST],
                SQL_SQL92_PREDICATES = ODBC[SQL_SP][All],
                SQL_AGGREGATE_FUNCTIONS = ODBC[SQL_AF][All],

                // Date/time scalar functions — DuckDB supports all standard date/time functions.
                // The Flight SQL driver only reports a subset; override to enable full folding.
                SQL_TIMEDATE_FUNCTIONS = ODBC[Flags]({
                    ODBC[SQL_FN_TD][SQL_FN_TD_NOW],
                    ODBC[SQL_FN_TD][SQL_FN_TD_CURDATE],
                    ODBC[SQL_FN_TD][SQL_FN_TD_DAYOFMONTH],
                    ODBC[SQL_FN_TD][SQL_FN_TD_DAYOFWEEK],
                    ODBC[SQL_FN_TD][SQL_FN_TD_DAYOFYEAR],
                    ODBC[SQL_FN_TD][SQL_FN_TD_MONTH],
                    ODBC[SQL_FN_TD][SQL_FN_TD_QUARTER],
                    ODBC[SQL_FN_TD][SQL_FN_TD_WEEK],
                    ODBC[SQL_FN_TD][SQL_FN_TD_YEAR],
                    ODBC[SQL_FN_TD][SQL_FN_TD_CURTIME],
                    ODBC[SQL_FN_TD][SQL_FN_TD_HOUR],
                    ODBC[SQL_FN_TD][SQL_FN_TD_MINUTE],
                    ODBC[SQL_FN_TD][SQL_FN_TD_SECOND],
                    ODBC[SQL_FN_TD][SQL_FN_TD_DAYNAME],
                    ODBC[SQL_FN_TD][SQL_FN_TD_MONTHNAME],
                    ODBC[SQL_FN_TD][SQL_FN_TD_CURRENT_DATE],
                    ODBC[SQL_FN_TD][SQL_FN_TD_CURRENT_TIME],
                    ODBC[SQL_FN_TD][SQL_FN_TD_CURRENT_TIMESTAMP],
                    ODBC[SQL_FN_TD][SQL_FN_TD_EXTRACT],
                    ODBC[SQL_FN_TD][SQL_FN_TD_TIMESTAMPADD],
                    ODBC[SQL_FN_TD][SQL_FN_TD_TIMESTAMPDIFF]
                }),

                // SQL-92 datetime functions (CURRENT_DATE, CURRENT_TIME, CURRENT_TIMESTAMP)
                SQL_SQL92_DATETIME_FUNCTIONS = ODBC[Flags]({
                    ODBC[SQL_SDF][SQL_SDF_CURRENT_DATE],
                    ODBC[SQL_SDF][SQL_SDF_CURRENT_TIME],
                    ODBC[SQL_SDF][SQL_SDF_CURRENT_TIMESTAMP]
                }),

                // SQL-92 numeric value functions (EXTRACT, CHAR_LENGTH, etc.)
                SQL_SQL92_NUMERIC_VALUE_FUNCTIONS = ODBC[Flags]({
                    ODBC[SQL_SNVF][SQL_SNVF_EXTRACT],
                    ODBC[SQL_SNVF][SQL_SNVF_CHAR_LENGTH],
                    ODBC[SQL_SNVF][SQL_SNVF_CHARACTER_LENGTH],
                    ODBC[SQL_SNVF][SQL_SNVF_OCTET_LENGTH],
                    ODBC[SQL_SNVF][SQL_SNVF_POSITION]
                }),

                // SQL-92 string functions
                SQL_SQL92_STRING_FUNCTIONS = ODBC[Flags]({
                    ODBC[SQL_SSF][SQL_SSF_CONVERT],
                    ODBC[SQL_SSF][SQL_SSF_LOWER],
                    ODBC[SQL_SSF][SQL_SSF_UPPER],
                    ODBC[SQL_SSF][SQL_SSF_SUBSTRING],
                    ODBC[SQL_SSF][SQL_SSF_TRIM_BOTH],
                    ODBC[SQL_SSF][SQL_SSF_TRIM_LEADING],
                    ODBC[SQL_SSF][SQL_SSF_TRIM_TRAILING]
                }),

                // SQL-92 value expressions (CASE, CAST, COALESCE, NULLIF)
                SQL_SQL92_VALUE_EXPRESSIONS = ODBC[Flags]({
                    ODBC[SQL_SVE][SQL_SVE_CASE],
                    ODBC[SQL_SVE][SQL_SVE_CAST],
                    ODBC[SQL_SVE][SQL_SVE_COALESCE],
                    ODBC[SQL_SVE][SQL_SVE_NULLIF]
                }),

                // SQL-92 relational join operators — DuckDB supports all standard joins.
                SQL_SQL92_RELATIONAL_JOIN_OPERATORS = ODBC[Flags]({
                    ODBC[SQL_SRJO][SQL_SRJO_CROSS_JOIN],
                    ODBC[SQL_SRJO][SQL_SRJO_INNER_JOIN],
                    ODBC[SQL_SRJO][SQL_SRJO_LEFT_OUTER_JOIN],
                    ODBC[SQL_SRJO][SQL_SRJO_RIGHT_OUTER_JOIN],
                    ODBC[SQL_SRJO][SQL_SRJO_FULL_OUTER_JOIN],
                    ODBC[SQL_SRJO][SQL_SRJO_NATURAL_JOIN]
                })
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
