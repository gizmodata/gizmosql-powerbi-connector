[Version = "2.0.1"]
section GizmoSQL;

// Diagnostics module for trace logging (disable for release builds)
EnableTraceOutput = false;

Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Extension.LoadExpression = Extension.LoadFunction;

Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value;
Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result;
Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();

GizmoSqlGenerator = Extension.LoadExpression("SqlGenerator.pqm");

// `Adbc.Connection` / `SqlView.Generator` are the newer (experimental) ADBC
// extensibility APIs, replacing `Adbc.DataSource`. The key difference: the
// first argument to SqlView.Generator is a unique identifier the engine uses
// to decide whether two queries point at the same data source — which is what
// lets cross-table joins fold in DirectQuery (issue #2 /
// microsoft/vscode-powerquery-sdk#409: Adbc.DataSource rejected them with
// FoldingFailureException "different data sources" at VisitJoinCore).
Adbc.Connection =
    try
        #shared[Adbc.Connection]
    otherwise
        (driver, databaseProperties, connectionProperties, options) =>
            error Error.Record("Expression.Error", "Adbc.Connection is not available in this Power BI Desktop version. Update to a recent build.");

SqlView.Generator =
    try
        #shared[SqlView.Generator]
    otherwise
        (uniqueIdentifier, sqlGenerator, getData) =>
            error Error.Record("Expression.Error", "SqlView.Generator is not available in this Power BI Desktop version. Update to a recent build.");

// Stock Apache Arrow Flight SQL ADBC driver (Go) — same driver and discovery
// mechanism as the previous Adbc.DataSource configuration.
Driver = [
    Name = "FlightSqlAdbcGizmoSQL",
    Folder = "FlightSQL",
    File = "libadbc_driver_flightsql.dll",
    DriverType = "Unmanaged",
    EntryPoint = "FlightSqlDriverInit"
];

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

// Map the current credential to Flight SQL ADBC database options.
GetCredentialProperties = () as record =>
    let
        Credential = Extension.CurrentCredential(),
        kind = Credential[AuthenticationKind]?
    in
        if kind = "UsernamePassword" then
            [ username = Credential[Username], password = Credential[Password] ]
        else if kind = "Key" then
            [ #"adbc.flight.sql.authorization_header" = "Bearer " & Credential[Key] ]
        else if kind = "OAuth" then
            // The OAuth poll returns the IdP's raw ID token, not a GizmoSQL
            // session JWT — sending it as a Bearer header fails with "invalid
            // token issuer". Present it through the Flight handshake instead
            // (username "token", JWT as password — same convention as JDBC and
            // gizmosql-ui): the server verifies it via JWKS
            // (VerifyAndDecodeBootstrapToken) and issues its own session JWT
            // for subsequent calls.
            [ username = "token", password = Credential[access_token] ]
        else
            error Error.Record("Error", "Unsupported authentication kind");

[DataSource.Kind = "GizmoSQL", Publish = "GizmoSQL.Publish"]
shared GizmoSQL.Contents = Value.ReplaceType(GizmoSQLImpl, GizmoSQL.ContentsType);

GizmoSQLImpl = (server as text, port as number, optional useEncryption as logical, optional disableCertificateVerification as logical, optional defaultCatalog as text) as table =>
    let
        context = GizmoSqlContext(server, port, useEncryption, disableCertificateVerification, defaultCatalog),
        result = GetDatabases(context)
    in
        Diagnostics.LogValue2(
            "GizmoSQL/Connection",
            [ Server = server, Port = port, DefaultCatalog = defaultCatalog ],
            result
        );

GizmoSqlContext = (server as text, port as number, useEncryption as nullable logical, disableCertificateVerification as nullable logical, defaultCatalog as nullable text) =>
    let
        Uri = BuildUri(server, port, useEncryption),
        TlsProperties =
            if disableCertificateVerification = true then
                [ #"adbc.flight.sql.client_option.tls_skip_verify" = "true" ]
            else
                [],
        DatabaseProperties = [ uri = Uri ] & TlsProperties & GetCredentialProperties(),
        Catalog = if defaultCatalog <> null and defaultCatalog <> "" then defaultCatalog else null,
        ConnectionProperties = if Catalog <> null then [ adbc.connection.catalog = Catalog ] else [],
        Connection = Adbc.Connection(Driver, DatabaseProperties, ConnectionProperties, [ ConnectionPoolType = 2 ]),
        ExecuteQuery = (sql as text, optional opts as nullable record) =>
            let
                connectionProps =
                    if opts[Catalog]? <> null then [ adbc.connection.catalog = opts[Catalog] ] else ConnectionProperties,
                queryOptions = [
                    ConnectionProperties = connectionProps,
                    IsMetadata = opts[IsMetadata]?
                ]
            in
                Connection[ExecuteQuery](sql, null, queryOptions),
        GetData = (query as text, resultType as type, foldContext) => CreateDataTable(query, resultType, foldContext, ExecuteQuery),
        // Data-source identity for the SqlView engine: two tables can fold into
        // a single native query (e.g. a DirectQuery join) only if their
        // identifiers compare equal. Keyed on the connection target only —
        // never include credentials here.
        UniqueIdentifier = [ Module = ModuleIdentifier, Signature = [ Uri = Uri, Catalog = Catalog ] ],
        SqlGenerator = SqlView.Generator(UniqueIdentifier, GizmoSqlGenerator, GetData)
    in
        [
            ExecuteQuery = ExecuteQuery,
            SqlGenerator = SqlGenerator,
            DefaultCatalog = Catalog
        ];

ModuleIdentifier = () => ...;

CreateDataTable = (query as text, resultType as type, foldContext, executeQuery) =>
    Table.View(null, [
        GetType = () => resultType,
        GetRows = () =>
            let
                data = executeQuery(query, foldContext[[Catalog], [IsMetadata]]?),
                oldNames = Table.ColumnNames(data),
                newNames = Table.ColumnNames(#table(resultType, {})),
                renamed = Table.RenameColumns(data, List.Zip({oldNames, newNames}))
            in
                renamed
    ]);

EscapeIdentifier = (identifier as text) as text => """" & Text.Replace(identifier, """", """""") & """";

EscapeStringLiteral = (value as text) as text => "'" & Text.Replace(value, "'", "''") & "'";

MakeNavTableType = (isLeaf) =>
    let
        dataType = type table meta [
            NavigationTable.ItemKind = "Table",
            Preview.Delay = "Table",
            NavigationTable.RowConfigurationColumn = "Kind"
        ],
        tableType = type table [
            Name = text,
            Description = nullable text,
            Data = dataType,
            Kind = text
        ],
        withKeys = Type.ReplaceTableKeys(tableType, {[Columns = {"Name", "Kind"}, Primary = true]}) meta [
            NavigationTable.NameColumn = "Name",
            NavigationTable.DataColumn = "Data",
            NavigationTable.KindColumn = "Kind"
        ]
    in
        withKeys;

GetDatabases = (context) =>
    let
        isLeaf = false,
        kind = "Database",
        catalogFilter =
            if context[DefaultCatalog] <> null then
                " WHERE catalog_name = " & EscapeStringLiteral(context[DefaultCatalog])
            else
                "",
        command = "SELECT DISTINCT catalog_name as name FROM information_schema.schemata" & catalogFilter,
        tables = context[ExecuteQuery](command, [IsMetadata = true]),
        getSchemas = (name) => GetSchemas(context, name),
        withData = Table.AddColumn(tables, "Data", each getSchemas([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind", each kind meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getSchemas, kind),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetSchemas = (context, catalog) =>
    let
        isLeaf = false,
        kind = "Schema",
        command = "SELECT schema_name as name FROM information_schema.schemata WHERE catalog_name = " & EscapeStringLiteral(catalog)
            & " AND schema_name NOT IN ('information_schema', 'pg_catalog')",
        schemas = context[ExecuteQuery](command, [IsMetadata = true]),
        getTables = (name) => GetTables(context, catalog, name),
        withData = Table.AddColumn(schemas, "Data", each getTables([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind", each kind meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getTables, kind),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetTables = (context, catalog, schema) =>
    let
        isLeaf = true,
        kind = {"Table", "View"},
        command = "SELECT table_name as name, table_type FROM information_schema.tables WHERE table_catalog = " & EscapeStringLiteral(catalog)
            & " AND table_schema = " & EscapeStringLiteral(schema),
        tables = context[ExecuteQuery](command, [IsMetadata = true]),
        getTable = (name) => GetTable(context, catalog, schema, name),
        withData = Table.AddColumn(tables, "Data", each getTable([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind",
            each (if [table_type] = "VIEW" then "View" else "Table") meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getTable, kind, true),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetTable = (context, catalog, schema, table) =>
    let
        tableType = GetTableType(context[ExecuteQuery], catalog, schema, table),
        tableReference = [Kind = "FromTable", Table = [Catalog = catalog, Schema = schema, Name = table]],
        withSqlView = context[SqlGenerator](tableReference, tableType, [])
    in
        withSqlView;

FoldNavigationStep = (selector, loader, kind, optional immediate) =>
    let
        reduceAnd = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "And" then List.Combine({@reduceAnd(ast[Left]), @reduceAnd(ast[Right])}) else {ast},
        matchFieldAccess = (ast) => if ast[Kind] = "FieldAccess" and ast[Expression] = RowExpression.Row then ast[MemberName] else ...,
        matchConstant = (ast) => if ast[Kind] = "Constant" then ast[Value] else ...,
        matchIndex = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "Equals"
            then
                if ast[Left][Kind] = "FieldAccess"
                    then Record.AddField([], matchFieldAccess(ast[Left]), matchConstant(ast[Right]))
                    else Record.AddField([], matchFieldAccess(ast[Right]), matchConstant(ast[Left]))
            else ...,
        predicate1 = Record.Combine(List.Transform(reduceAnd(RowExpression.From(selector)), matchIndex)),
        isKindList = kind is list,
        kindMatch = if isKindList then List.Contains(kind, predicate1[Kind]?) else predicate1[Kind]? = kind,
        predicate2 = if kindMatch then Record.RemoveFields(predicate1, {"Kind"}) else predicate1,
        pickKind = if isKindList then
                       if List.Contains(kind, predicate1[Kind]?) then predicate1[Kind]? else ...
                   else kind,
        name = if Record.FieldCount(predicate2) = 1 and predicate2[Name]? <> null then predicate2[Name] else ...,

        dataResult = loader(name),
        emptyResult = #table(type table [Name = text, Description = nullable text, Data = table, Kind = text], {}),
        // A missing table surfaces as an error from the metadata queries; map
        // it to an empty navigation table instead of failing the fold.
        // TODO: "(42S02)" is an ODBC SQLSTATE inherited from quack-net — adjust
        // once the ADBC driver's missing-table error shape is known. A
        // non-matching error just re-raises here, and ThrowFoldingFailures =
        // false makes the engine fall back to the unfolded path.
        resultOrEmpty = if immediate = true
            then try dataResult catch (e) => if Text.Contains(e[Message] ?? "", "(42S02)") then null else error e
            else dataResult
    in
        if resultOrEmpty = null
            then emptyResult
            else Table.FromRecords({[Name = name, Description = "", Data = resultOrEmpty, Kind = pickKind]});

GetTableType = (exec, catalog, schema, table) =>
    let
        qualifiedName = EscapeIdentifier(catalog) & "." & EscapeIdentifier(schema) & "." & EscapeIdentifier(table),
        command = "SELECT "
            & "name AS column_name, "
            & "type AS data_type, "
            & "CASE WHEN ""notnull"" THEN 'NO' ELSE 'YES' END AS is_nullable, "
            & "TRY_CAST(regexp_extract(type, '^DECIMAL\((\d+),\s*\d+\)$', 1) AS INTEGER) AS numeric_precision, "
            & "TRY_CAST(regexp_extract(type, '^DECIMAL\(\d+,\s*(\d+)\)$', 1) AS INTEGER) AS numeric_scale, "
            & "NULL::INTEGER AS character_maximum_length "
            & "FROM pragma_table_info(" & EscapeStringLiteral(qualifiedName) & ") "
            & "ORDER BY cid",
        columnInfo = Table.Buffer(exec(command, [IsMetadata = true])),
        columnNames = columnInfo[column_name],
        columnTypes = List.Transform(Table.ToRecords(columnInfo), each [
            Type = GetColumnType([data_type], [is_nullable], [numeric_precision], [numeric_scale], [character_maximum_length]),
            Optional = false
        ]),
        rowType = Type.ForRecord(Record.FromList(columnTypes, columnNames), false),
        primaryKeys = GetPrimaryKeys(exec, catalog, schema, table),
        tableType = type table rowType,
        tableTypeWithPrimaryKey = Type.ReplaceTableKeys(tableType, primaryKeys)
    in
        tableTypeWithPrimaryKey;

// Parse the base type from potentially parameterized data_type values like "DECIMAL(18,2)" or "INTEGER[]"
ParseBaseType = (dataType as text) as text =>
    let
        parenPos = Text.PositionOf(dataType, "("),
        bracketPos = Text.PositionOf(dataType, "["),
        endPos = List.Min(List.RemoveNulls({
            if parenPos >= 0 then parenPos else null,
            if bracketPos >= 0 then bracketPos else null,
            Text.Length(dataType)
        })),
        baseType = Text.Upper(Text.Trim(Text.Start(dataType, endPos)))
    in
        baseType;

AdjustType = (nullable as logical, mtype as type, nativeTypeName as text) =>
    let
        withNullable = if nullable then type nullable mtype else mtype,
        withFacets = Type.ReplaceFacets(withNullable, [NativeTypeName = nativeTypeName])
    in
        withFacets;

ColumnTypeMap = [
    BOOLEAN = type logical,
    TINYINT = Int32.Type,
    SMALLINT = Int32.Type,
    INTEGER = Int32.Type,
    BIGINT = Int64.Type,
    HUGEINT = Decimal.Type,
    UTINYINT = Int32.Type,
    USMALLINT = Int32.Type,
    UINTEGER = Int64.Type,
    UBIGINT = Decimal.Type,
    FLOAT = Double.Type,
    DOUBLE = Double.Type,
    DECIMAL = Decimal.Type,
    VARCHAR = type text,
    BLOB = type binary,
    DATE = type date,
    TIME = type time,
    TIMESTAMP = type datetime,
    #"TIMESTAMP WITH TIME ZONE" = type datetimezone,
    TIMESTAMPTZ = type datetimezone,
    TIMESTAMP_S = type datetime,
    TIMESTAMP_MS = type datetime,
    TIMESTAMP_NS = type datetime,
    INTERVAL = type text,
    UUID = type text,
    JSON = type text,
    BIT = type text,
    ENUM = type text,
    LIST = type text,
    STRUCT = type text,
    MAP = type text,
    UNION = type text,
    ARRAY = type text
];

GetColumnType = (dataType as text, isNullableText as text, numericPrecision, numericScale, charMaxLength) =>
    let
        baseType = ParseBaseType(dataType),
        isNullable = isNullableText = "YES",
        mtype = Record.FieldOrDefault(ColumnTypeMap, baseType, type text),
        adjustedType = if baseType = "DECIMAL" and numericPrecision <> null then
            Type.ReplaceFacets(
                AdjustType(isNullable, Decimal.Type, "DECIMAL"),
                [NativeTypeName = "DECIMAL", NumericPrecisionBase = 10, NumericPrecision = numericPrecision, NumericScale = numericScale ?? 0])
        else if baseType = "VARCHAR" and charMaxLength <> null then
            Type.ReplaceFacets(
                AdjustType(isNullable, type text, "VARCHAR"),
                [NativeTypeName = "VARCHAR", MaxLength = charMaxLength, IsVariableLength = true])
        else
            AdjustType(isNullable, mtype, baseType)
    in
        adjustedType;

GetPrimaryKeys = (exec, catalog, schema, table) =>
    let
        command = "SELECT column_name FROM information_schema.table_constraints tc "
            & "JOIN information_schema.key_column_usage kcu "
            & "ON tc.constraint_name = kcu.constraint_name "
            & "AND tc.table_catalog = kcu.table_catalog "
            & "AND tc.table_schema = kcu.table_schema "
            & "AND tc.table_name = kcu.table_name "
            & "WHERE tc.constraint_type = 'PRIMARY KEY' "
            & "AND tc.table_catalog = " & EscapeStringLiteral(catalog) & " "
            & "AND tc.table_schema = " & EscapeStringLiteral(schema) & " "
            & "AND tc.table_name = " & EscapeStringLiteral(table) & " "
            & "ORDER BY kcu.ordinal_position",
        result = try exec(command, [IsMetadata = true]) otherwise #table({"column_name"}, {}),
        primaryKeyColumns = result[column_name]
    in
        if List.IsEmpty(primaryKeyColumns) then {} else {[Columns = primaryKeyColumns, Primary = true]};

// --- OAuth (browser SSO) ---
// GizmoSQL Enterprise server-side OAuth: GET /oauth/initiate returns
// { session_uuid, auth_url }; the user signs in at auth_url; the IdP redirects
// to the server's /oauth/callback, which exchanges the authorization code for
// the IdP's ID token; GET /oauth/token/{session_uuid} returns
// { status: pending | complete | error | not_found, token? } where token is
// that raw ID token. The connector then presents it through the Flight
// handshake (username "token") and the server issues its session JWT — see
// GetCredentialProperties.
// The OAuth HTTP endpoint listens on --oauth-port (default 31339) on the same
// host as the Flight SQL endpoint. Note: Web.Contents cannot skip TLS
// verification, so the OAuth endpoint's certificate must be trusted by the
// client machine (unlike the gRPC channel, which honors
// disableCertificateVerification).
OAuthDefaultPort = 31339;
OAuthPollIntervalSeconds = 1;
OAuthPollAttempts = 60;

// Always https: the data source path only carries required parameters
// (server/port), so useEncryption is not available here — and OAuth/SSO
// deployments register https redirect URIs with their IdP anyway. Use
// username/password or Key auth against TLS-disabled dev servers.
OAuthBaseUrl = (dataSourcePath as text) as text =>
    let
        json = Json.Document(dataSourcePath)
    in
        "https://" & json[server] & ":" & Number.ToText(OAuthDefaultPort);

StartLogin = (resourceUrl, state, display) =>
    let
        base = OAuthBaseUrl(resourceUrl),
        initiate = Json.Document(Web.Contents(base & "/oauth/initiate")),
        result = [
            LoginUri = initiate[auth_url],
            CallbackUri = base & "/oauth/callback",
            WindowHeight = 800,
            WindowWidth = 1024,
            Context = [ BaseUrl = base, SessionUuid = initiate[session_uuid] ]
        ]
    in
        Diagnostics.LogValue2("GizmoSQL/OAuth/StartLogin", [ BaseUrl = base ], result);

FinishLogin = (context, callbackUri, state) =>
    let
        // The embedded browser closes on navigation to /oauth/callback, which
        // can happen before the server has processed the code exchange.
        // Replaying the callback request is harmless when the exchange already
        // completed and delivers the authorization code when it did not.
        replayed = try Binary.Length(Web.Contents(callbackUri, [ IsRetry = true ])) otherwise 0,
        token = if replayed >= 0 then PollForToken(context[BaseUrl], context[SessionUuid], OAuthPollAttempts) else error ""
    in
        [ access_token = token, token_type = "bearer" ];

PollForToken = (baseUrl as text, sessionUuid as text, attemptsLeft as number) =>
    let
        // IsRetry bypasses the M engine's request cache so each poll hits the server.
        response = Json.Document(Web.Contents(baseUrl & "/oauth/token/" & sessionUuid, [ IsRetry = true ])),
        status = response[status]?
    in
        if status = "complete" then
            response[token]
        else if status = "pending" then
            if attemptsLeft <= 0 then
                error Error.Record("Error", "OAuth sign-in timed out waiting for the token. Please try again.")
            else
                Function.InvokeAfter(
                    () => PollForToken(baseUrl, sessionUuid, attemptsLeft - 1),
                    #duration(0, 0, 0, OAuthPollIntervalSeconds)
                )
        else if status = "error" then
            error Error.Record("Error", "OAuth sign-in failed: " & (response[#"error"]? ?? "unknown error"))
        else if status = "not_found" then
            error Error.Record("Error", "OAuth session expired before sign-in completed. Please try again.")
        else
            error Error.Record("Error", "Unexpected OAuth token status: " & (status ?? "(none)"));

// Data source definition
GizmoSQL = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath)
        in
            { "GizmoSQL.Contents", json[server], json[port], json[useEncryption]?, json[disableCertificateVerification]?, json[defaultCatalog]? },
    Authentication = [
        UsernamePassword = [],
        Key = [],
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Label = "OAuth (Browser)"
        ]
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
    SourceImage = GizmoSQL.Icons,
    SourceTypeImage = GizmoSQL.Icons
];

GizmoSQL.Icons = [
    Icon16 = { Extension.Contents("GizmoSQL16.png"), Extension.Contents("GizmoSQL20.png"), Extension.Contents("GizmoSQL24.png"), Extension.Contents("GizmoSQL32.png") },
    Icon32 = { Extension.Contents("GizmoSQL32.png"), Extension.Contents("GizmoSQL40.png"), Extension.Contents("GizmoSQL48.png"), Extension.Contents("GizmoSQL64.png") }
];
