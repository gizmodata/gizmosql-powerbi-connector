// Licensed under the Apache License, Version 2.0
//
// GizmoSQL Power BI custom connector.
//
// Loads the native AOT ADBC driver (gizmosql_adbc.dll) via the M engine's
// Adbc.Connection function. The driver must be installed at:
//   <Power BI Desktop install>\bin\ADBC Drivers\GizmoSql\gizmosql_adbc.dll
//
// The navigation-table and query-folding plumbing (SqlGenerator.pqm /
// SqlGeneratorCommon.pqm and the GetDatabases/GetSchemas/GetTables/GetTableType
// helpers) targets DuckDB SQL, which GizmoSQL serves natively.

[ Version = "1.0.0" ]
section GizmoSql;

Driver = [
    Name = "GizmoSqlAdbc",
    Folder = "GizmoSql",
    File = "gizmosql_adbc.dll",
    DriverType = "Unmanaged",
    EntryPoint = "GizmoSqlAdbcDriverInit"
];

EscapeIdentifier = (identifier as text) as text => """" & Text.Replace(identifier, """", """""") & """";

EscapeStringLiteral = (value as text) as text =>
    "'" & Text.Replace(value, "'", "''") & "'";

AddConnectionStringOption = (options as record, name as text, value as any, optional metadata) as record =>
    if value = null then
        options
    else
        Record.AddField(options, name, value meta (metadata ?? []));

ValidateOptions = (options) as record =>
    let
        ValidOptionsMap = #table({"Name", "Type", "Description", "Default", "Validate", "Hidden"},
            {
                {"SqlStatement", type nullable text, Extension.LoadString("ValidTextValue"), null, each _ = null or _ is text, false}
            }),
        ValidatedOptions = GetValidatedOptions(options, ValidOptionsMap)
    in
        ValidatedOptions;

GetValidatedOptions = (options, ValidOptionsMap) =>
    let
        VisibleKeys = Table.SelectRows(ValidOptionsMap, each not [Hidden])[Name],
        ValidKeys = Table.Column(ValidOptionsMap, "Name"),
        InvalidKeys = List.Difference(Record.FieldNames(options), ValidKeys),
        InvalidKeysText = if List.IsEmpty(InvalidKeys) then null else Text.Format(Extension.LoadString("InvalidOptionsKey"), {Text.Combine(InvalidKeys, ", "), Text.Combine(VisibleKeys, ", ")}),
        ValidateValue = (name, optionType, description, default, validate, value) =>
            if (value is null and (Type.IsNullable(optionType) or default <> null))
                or (Type.Is(Value.Type(value), optionType) and validate(value)) then null
            else Text.Format(Extension.LoadString("InvalidOptionsValue"), {name, value, description}),
        InvalidValues = List.RemoveNulls(Table.TransformRows(ValidOptionsMap,
            each ValidateValue([Name], [Type], [Description], [Default], [Validate], Record.FieldOrDefault(options, [Name], [Default])))),
        DefaultOptions = Record.FromTable(Table.RenameColumns(Table.SelectColumns(ValidOptionsMap, {"Name", "Default"}), {"Default", "Value"})),
        NullNotAllowedFields = List.RemoveNulls(Table.TransformRows(ValidOptionsMap,
            each if not Type.IsNullable([Type]) and null = Record.FieldOrDefault(options, [Name], [Default]) then [Name] else null)),
        NormalizedOptions = DefaultOptions & Record.RemoveFields(options, NullNotAllowedFields, MissingField.Ignore),
        Result = if null = options then DefaultOptions
                 else if not List.IsEmpty(InvalidKeys) then
                     error Error.Record("Expression.Error", InvalidKeysText)
                 else if not List.IsEmpty(InvalidValues) then
                     error Error.Record("Expression.Error", Text.Combine(InvalidValues, ", "))
                 else NormalizedOptions
    in
        Result;

[DataSource.Kind = "GizmoSql", Publish = "GizmoSql.Publish"]
shared GizmoSql.Database = Value.ReplaceType(GizmoSql.Function, GizmoSql.Type);

// server is the only required field. The optional SqlStatement option renders
// as a large, collapsible "SQL statement" box under Advanced Options (record
// fields with Formatting.IsMultiLine render multi-line, matching the built-in
// ODBC connector): leave it empty to get the catalog/schema/table navigator,
// or type SQL to run it and import the result.
GizmoSql.Function = (server as text, optional skipTlsVerification as logical, optional options as nullable record) as table =>
    let
        validatedOptions = ValidateOptions(options),
        context = GizmoSqlContext(server, skipTlsVerification ?? false),
        sql = validatedOptions[SqlStatement]?,
        result =
            if sql <> null and Text.Trim(sql) <> "" then
                context[ExecuteQuery](sql, [])
            else
                GetDatabases(context)
    in
        result;

GizmoSqlContext = (server as text, skipVerify as logical) =>
    let
        // Normalize the server address to a full Flight SQL URI. Accept a bare
        // "host:port" or "host" and default to grpc+tls with the standard port.
        Uri = if Text.Contains(server, "://") then server
              else if Text.Contains(server, ":") then "grpc+tls://" & server
              else "grpc+tls://" & server & ":31337",
        SkipTls = if skipVerify then "true" else "false",
        // ADBC connection-string keys match GizmoSqlParameters.* constants.
        BaseOptions = [
            #"adbc.gizmosql.server_address" = Uri,
            #"adbc.gizmosql.username" = Extension.CurrentCredential()[Username],
            #"adbc.gizmosql.password" = Extension.CurrentCredential()[Password],
            #"adbc.gizmosql.auth.type" = "password",
            #"adbc.gizmosql.tls.skip_verify" = SkipTls
        ],
        ConnectionString = BaseOptions,
        Connection = Adbc.Connection(Driver, ConnectionString, [], [ConnectionPoolType = 2]),
        ExecuteQueryCtor = (cxn) => (sql, optional opts) =>
            let
                connectionProps = if opts[Catalog]? <> null then [adbc.connection.catalog = opts[Catalog]] else [],
                queryOptions = [
                    ConnectionProperties = connectionProps,
                    IsMetadata = opts[IsMetadata]?
                ]
            in
                cxn[ExecuteQuery](sql, null, queryOptions),
        GetData = (query as text, resultType as type, ctx) => CreateDataTable(query, resultType, ctx, context[ExecuteQuery]),
        UniqueIdentifier = MakeUniqueIdentifier(ConnectionString),
        SqlGenerator = SqlView.Generator(UniqueIdentifier, GizmoSqlSqlGenerator, GetData),
        context = [
            Connection = Connection,
            ExecuteQuery = ExecuteQueryCtor(Connection),
            ExecuteQueryCtor = ExecuteQueryCtor,
            SqlGenerator = SqlGenerator
        ]
    in
        context;

CreateDataTable = (query as text, resultType as type, context, executeQuery) =>
    Table.View(null, [
        GetType = () => resultType,
        GetRows = () =>
            let
                data = executeQuery(query, context[[Catalog],[IsMetadata]]?),
                oldNames = Table.ColumnNames(data),
                newNames = Table.ColumnNames(#table(resultType, {})),
                renamed = Table.RenameColumns(data, List.Zip({oldNames, newNames}))
            in
                renamed
    ]);

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
        withKeys = Type.ReplaceTableKeys(tableType, {[Columns={"Name", "Kind"}, Primary=true]}) meta [
            NavigationTable.NameColumn="Name",
            NavigationTable.DataColumn="Data",
            NavigationTable.KindColumn="Kind"
        ]
    in
        withKeys;

GetDatabases = (context) =>
    let
        isLeaf = false,
        kind = "Database",
        command = "SELECT DISTINCT catalog_name as name FROM information_schema.schemata",
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
        kind = {"Table","View"},
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
        kindMatch = if isKindList then List.Contains(kind,predicate1[Kind]?) else predicate1[Kind]? = kind,
        predicate2 = if kindMatch then Record.RemoveFields(predicate1, {"Kind"}) else predicate1,
        pickKind = if isKindList then
                       if List.Contains(kind,predicate1[Kind]?) then predicate1[Kind]? else ...
                   else kind,
        name = if Record.FieldCount(predicate2) = 1 and predicate2[Name]? <> null then predicate2[Name] else ...,

        // TODO: Make Description work when folding

        dataResult = loader(name),
        emptyResult = #table(type table [Name = text, Description = nullable text, Data = table, Kind = text], {}),
        resultOrEmpty = if immediate = true
            // TODO: Adjust this for error shape
            then try dataResult catch (e) => if Text.Contains(e[Message], "(42S02)") then null else error e
            else dataResult
    in
        if resultOrEmpty = null
            then emptyResult
            else Table.FromRecords({[Name=name, Description="", Data=resultOrEmpty, Kind=pickKind]});

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

ModuleIdentifier = () => ...;
MakeUniqueIdentifier = (connectionString) => [Module = ModuleIdentifier, Signature = connectionString];

// Type for the exported function. The SQL statement lives as a field of the
// optional `options` record (not a top-level parameter), because record fields
// honor Formatting.IsMultiLine and render under Advanced Options as a large,
// collapsible box — exactly like the built-in ODBC connector. Top-level
// parameters ignore IsMultiLine and stay single-line.
GizmoSql.Type = type function (
    server as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("DatabaseParameterCaption"),
        Documentation.SampleValues = { "grpc+tls://localhost:31337" }
    ]),
    optional skipTlsVerification as (type logical meta [
        Documentation.FieldCaption = Extension.LoadString("SkipTlsVerificationCaption"),
        Documentation.SampleValues = { false }
    ]),
    optional options as (type [
        optional SqlStatement = (type text meta [
            Documentation.FieldCaption = Extension.LoadString("SqlStatementCaption"),
            Formatting.IsMultiLine = true,
            Formatting.IsCode = true
        ])
    ] meta [
        Documentation.FieldCaption = Extension.LoadString("OptionsParameterCaption")
    ])
) as table meta [
    Documentation.Name = "GizmoSQL",
    Documentation.Caption = Extension.LoadString("FormulaTitle"),
    Documentation.Description = Extension.LoadString("GizmoSql_Description"),
    Documentation.LongDescription = Extension.LoadString("GizmoSql_LongDescription")
];

// DataSource.Kind definition
GizmoSql = [
    Description = "GizmoSQL",
    Type = "Custom",
    MakeResourcePath = (server) => server,
    ParseResourcePath = (resourcePath) => {resourcePath},
    TestConnection = (resourcePath) => { "GizmoSql.Database" } & {resourcePath},
    Authentication = [
        UsernamePassword = []
    ]
];

GizmoSql.Publish = [
    Beta = true,
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    Category = "Database",
    SupportsDirectQuery = true,
    SourceImage = GizmoSql.Icons,
    SourceTypeImage = GizmoSql.Icons
];

GizmoSql.Icons = [
    Icon16 = { Extension.Contents("GizmoSql16.png"), Extension.Contents("GizmoSql20.png"), Extension.Contents("GizmoSql24.png"), Extension.Contents("GizmoSql32.png") },
    Icon32 = { Extension.Contents("GizmoSql32.png"), Extension.Contents("GizmoSql40.png"), Extension.Contents("GizmoSql48.png"), Extension.Contents("GizmoSql64.png") }
];

// Extension library functions
Extension.LoadExpression = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

GizmoSqlSqlGenerator = Extension.LoadExpression("SqlGenerator.pqm");

Adbc.Connection = try #shared[Adbc.Connection] otherwise (driver, databaseProperties, connectionProperties, options) =>
    error Error.Record("Expression.Error", "The Adbc.Connection function is not available in this environment");
SqlView.Generator = try #shared[SqlView.Generator] otherwise (uniqueIdentifier, sqlGenerator, getData) =>
    error Error.Record("Expression.Error", "The SqlView.Generator function is not available in this environment");
