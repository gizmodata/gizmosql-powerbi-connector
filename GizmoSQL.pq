[Version = "2.0.0"]
section GizmoSQL;

Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Extension.LoadExpression = Extension.LoadFunction;

// Diagnostics module for trace logging (disable for release builds)
EnableTraceOutput = false;

Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value;
Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result;
Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();

GizmoSqlGenerator = Extension.LoadExpression("SqlGenerator.pqm");
FlightSqlAdbcConfig = Extension.LoadExpression("FlightSqlAdbcConfig.pqm");

// `Adbc.DataSource` / `Adbc.Query` are available in current Power BI Desktop releases.
// Wrap with try/otherwise so build/load on older hosts surfaces a clear error.
Adbc.DataSource =
    try
        #shared[Adbc.DataSource]
    otherwise
        (driver, connectionString, options) =>
            error Error.Record("Expression.Error", "Adbc.DataSource is not available in this Power BI Desktop version. Update to a recent build (Aug 2025+).");

Adbc.Query =
    try
        #shared[Adbc.Query]
    otherwise
        (driver, connectionString, query) =>
            error Error.Record("Expression.Error", "Adbc.Query is not available in this Power BI Desktop version.");

// "Get Data" dialog parameters — kept to match the v1.x ODBC connector
GizmoSQL.ContentsType = type function (
    server as (type text meta [
        Documentation.FieldCaption = "Server",
        Documentation.FieldDescription = "Hostname or IP address of the GizmoSQL server",
        Documentation.SampleValues = {"localhost"}
    ]),
    port as (type number meta [
        Documentation.FieldCaption = "Port",
        Documentation.FieldDescription = "Flight SQL gRPC port of the GizmoSQL server",
        Documentation.SampleValues = {31337}
    ]),
    optional useEncryption as (type logical meta [
        Documentation.FieldCaption = "Use Encryption (TLS)",
        Documentation.FieldDescription = "Connect with grpc+tls://; disable to use plain grpc://",
        Documentation.AllowedValues = {true, false}
    ]),
    optional disableCertificateVerification as (type logical meta [
        Documentation.FieldCaption = "Disable Certificate Verification",
        Documentation.FieldDescription = "Skip TLS certificate verification (not recommended for production)",
        Documentation.AllowedValues = {true, false}
    ]),
    optional defaultCatalog as (type text meta [
        Documentation.FieldCaption = "Default Catalog",
        Documentation.FieldDescription = "Database/catalog to use (leave blank for the server default)",
        Documentation.SampleValues = {"my_database"}
    ])
) as table;

// Build the gRPC URI from the server/port/encryption parameters.
BuildUri = (server as text, port as number, useEncryption as nullable logical) as text =>
    let
        scheme = if useEncryption = false then "grpc" else "grpc+tls"
    in
        scheme & "://" & server & ":" & Number.ToText(port);

// Adbc.DataSource expects CredentialConnectionString to evaluate to a record,
// not a function — pattern matches spiceai/powerbi-connector. Defining this as
// `() as record => ...` would pass the function itself, leaving auth unset.
//
// IMPORTANT: keep this body returning the credential record DIRECTLY. Wrapping
// the return value (e.g. through Diagnostics.LogValue2) makes it opaque to PBI's
// data-source-identity hashing, which can break cross-table query folding with
// "The left and right queries come from different data sources" — DirectQuery
// joins evaluate each table independently and need both `GizmoSQL.Contents(...)`
// calls to hash-equate, which requires fully transparent CredentialConnectionString.
GetCredentialConnectionString =
    let
        Credential = Extension.CurrentCredential(),
        kind = Credential[AuthenticationKind]?
    in
        if kind = "UsernamePassword" then
            [ username = Credential[Username], password = Credential[Password] ]
        else if kind = "Key" then
            [ #"adbc.flight.sql.authorization_header" = "Bearer " & Credential[Key] ]
        else
            error Error.Record("Error", "Unsupported authentication kind");

// Connector implementation extracted to a NAMED identifier (not an inline lambda).
// Mirrors spiceai/powerbi-connector — gives PBI's optimizer a stable function-value
// identity for the data-source-identity hash that powers cross-table fold detection.
GizmoSqlConnectionImpl = (server as text, port as number, optional useEncryption as logical, optional disableCertificateVerification as logical, optional defaultCatalog as text) as table =>
    let
        Uri = BuildUri(server, port, useEncryption),
        BaseConnectionString = [ uri = Uri ],
        WithTls =
            if disableCertificateVerification = true then
                Record.AddField(BaseConnectionString, "adbc.flight.sql.client_option.tls_skip_verify", "true")
            else
                BaseConnectionString,
        ConnectionString =
            if defaultCatalog <> null and defaultCatalog <> "" then
                Record.AddField(WithTls, "adbc.connection.catalog", defaultCatalog)
            else
                WithTls
    in
        Adbc.DataSource(
            FlightSqlAdbcConfig,
            ConnectionString,
            [
                SqlGenerator = GizmoSqlGenerator,
                CredentialConnectionString = GetCredentialConnectionString
            ]
        );

[DataSource.Kind = "GizmoSQL", Publish = "GizmoSQL.Publish"]
shared GizmoSQL.Contents = Value.ReplaceType(GizmoSqlConnectionImpl, GizmoSQL.ContentsType);

// Data source definition
GizmoSQL = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath)
        in
            { "GizmoSQL.Contents", json[server], json[port], json[useEncryption]?, json[disableCertificateVerification]?, json[defaultCatalog]? },
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
    SupportsDirectQuery = true,
    // NativeQueryProperties is officially ODBC-only per Microsoft's docs and was
    // empirically confirmed to be ignored on the Adbc.DataSource path (a fully populated
    // 3-level navigationSteps had no effect on the cross-table-join "different data
    // sources" error in DirectQuery). Kept here as a Spice-style placeholder for parity.
    NativeQueryProperties = [
        navigationSteps = {[]},
        nativeQueryOptions = [
            EnableFolding = true
        ]
    ],
    SourceImage = GizmoSQL.Icons,
    SourceTypeImage = GizmoSQL.Icons
];

GizmoSQL.Icons = [
    Icon16 = { Extension.Contents("GizmoSQL16.png"), Extension.Contents("GizmoSQL20.png"), Extension.Contents("GizmoSQL24.png"), Extension.Contents("GizmoSQL32.png") },
    Icon32 = { Extension.Contents("GizmoSQL32.png"), Extension.Contents("GizmoSQL40.png"), Extension.Contents("GizmoSQL48.png"), Extension.Contents("GizmoSQL64.png") }
];
