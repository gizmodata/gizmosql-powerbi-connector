[Version = "2.1.0"]
section GizmoSQL;

Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Extension.LoadExpression = Extension.LoadFunction;

Diagnostics = Extension.LoadFunction("Diagnostics.pqm");

// Debug tracing flag. Kept off in the data-source path: turning it on (true) makes
// Diagnostics.LogValue2 a real opaque function call, which can break PBI's
// data-source-identity hashing when GizmoSQL.Contents results are wrapped.
EnableTraceOutput = false;

Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value;
Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result;
Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();
Diagnostics.MaskCredentials = Diagnostics[MaskCredentials];

GizmoSqlGenerator = Extension.LoadExpression("SqlGenerator.pqm");
FlightSqlAdbcConfig = Extension.LoadExpression("FlightSqlAdbcConfig.pqm");

// Legacy ADBC navigator (kept — only path Adbc.DataSource currently supports for a
// foldable navigator in PBI Desktop 2.154 / Mashup 2.154.528). Per mattmasson on
// microsoft/vscode-powerquery-sdk#409 the long-term path is `Adbc.Connection` +
// `SqlView.Generator(uniqueIdentifier, ...)` for source-identity-aware joins, but
// that pipeline isn't fully exposed yet — `Adbc.DataSource` options only accept
// {ClientConnectionPooling, CreateNavigationProperties, CredentialConnectionString,
// SqlGenerator}, and the v1 SqlGenerator record rejects extra fields like SqlView/
// UniqueIdentifier. See connector README for the full investigation log.
Adbc.DataSource =
    try
        #shared[Adbc.DataSource]
    otherwise
        (driver, connectionProperties, options) =>
            error Error.Record("Expression.Error", "Adbc.DataSource is not available in this Power BI Desktop version. Update to a recent build (Aug 2025+).");

// New ADBC primitives — used here as a side-effect warmup so the AdditionalCacheKey
// gets registered on the connection-pool entry that Adbc.DataSource opens. If a future
// PBI build wires `SqlView.Generator` into the navigator path, switch over by passing
// the resulting view function via whatever option name lands.
Adbc.Connection =
    try
        #shared[Adbc.Connection]
    otherwise
        (driver, databaseProperties, connectionProperties, optional options) => null;

Adbc.Query =
    try
        #shared[Adbc.Query]
    otherwise
        (driver, connectionProperties, query, optional options) =>
            error Error.Record("Expression.Error", "Adbc.Query is not available in this Power BI Desktop version.");

SqlView.Generator =
    try
        #shared[SqlView.Generator]
    otherwise
        (uniqueIdentifier, sqlGenerator, getData) => null;

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

// Read credentials as a plain record. Used both as the Adbc.DataSource
// `CredentialConnectionString` option (so PBI keeps creds out of the URI) and as the
// `connectionProperties` arg to Adbc.Connection during the pool warmup.
GetCredentialProperties = () as record =>
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

// Source-identity key. Two `GizmoSQL.Contents(...)` calls with the same endpoint
// produce byte-identical strings here. Credentials are deliberately NOT mixed in:
// the same physical endpoint accessed by two callers with the same auth resolves
// to one logical source. Per mattmasson on microsoft/vscode-powerquery-sdk#409,
// this is the value `SqlView.Generator` would consume when the new API path lands.
BuildUniqueId = (server as text, port as number, useEncryption as nullable logical, defaultCatalog as nullable text) as text =>
    let
        scheme = if useEncryption = false then "grpc" else "grpc+tls",
        catalogPart = if defaultCatalog <> null and defaultCatalog <> "" then "/" & defaultCatalog else ""
    in
        "gizmosql://" & scheme & "://" & Text.Lower(server) & ":" & Number.ToText(port) & catalogPart;

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
                WithTls,

        CredentialProperties = GetCredentialProperties(),
        UniqueId = BuildUniqueId(server, port, useEncryption, defaultCatalog),

        // Pre-register the ADBC connection pool entry under our stable UniqueId so
        // PBI's source-identity layer has something to hash-equate when two
        // GizmoSQL.Contents calls reference the same endpoint (per mattmasson on #409).
        // The handle isn't used directly — Adbc.DataSource opens through the same pool.
        _PoolWarmup = Adbc.Connection(
            FlightSqlAdbcConfig,
            ConnectionString,
            CredentialProperties,
            [ AdditionalCacheKey = UniqueId ]
        )
    in
        // Force evaluation of _PoolWarmup so M doesn't elide it. The conditional is a
        // no-op control flow — either branch returns the navigator.
        if _PoolWarmup = null or _PoolWarmup <> null then
            Adbc.DataSource(
                FlightSqlAdbcConfig,
                ConnectionString,
                [
                    SqlGenerator = GizmoSqlGenerator,
                    CredentialConnectionString = CredentialProperties
                ]
            )
        else
            error "unreachable";

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
