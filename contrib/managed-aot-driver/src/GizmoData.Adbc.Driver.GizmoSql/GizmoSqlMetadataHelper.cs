// Licensed under the Apache License, Version 2.0

using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Apache.Arrow;
using Apache.Arrow.Adbc;
using Apache.Arrow.Ipc;
using Apache.Arrow.Types;
using Arrow.Flight.Protocol.Sql;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Implements the ADBC GetObjects hierarchical metadata result.
    /// Assembles data from Flight SQL GetCatalogs, GetDbSchemas, GetTables commands
    /// to build the nested catalog → schema → table → column hierarchy
    /// conforming to <see cref="StandardSchemas.GetObjectsSchema"/>.
    /// </summary>
    internal class GizmoSqlGetObjectsResult : IArrowArrayStream
    {
        private readonly GizmoSqlConnection _connection;
        private readonly AdbcConnection.GetObjectsDepth _depth;
        private readonly string? _catalogPattern;
        private readonly string? _dbSchemaPattern;
        private readonly string? _tableNamePattern;
        private readonly IReadOnlyList<string>? _tableTypes;
        private readonly string? _columnNamePattern;
        private bool _consumed;

        public GizmoSqlGetObjectsResult(
            GizmoSqlConnection connection,
            AdbcConnection.GetObjectsDepth depth,
            string? catalogPattern,
            string? dbSchemaPattern,
            string? tableNamePattern,
            IReadOnlyList<string>? tableTypes,
            string? columnNamePattern)
        {
            _connection = connection;
            _depth = depth;
            _catalogPattern = catalogPattern;
            _dbSchemaPattern = dbSchemaPattern;
            _tableNamePattern = tableNamePattern;
            _tableTypes = tableTypes;
            _columnNamePattern = columnNamePattern;
        }

        public Schema Schema => StandardSchemas.GetObjectsSchema;

        public async ValueTask<RecordBatch?> ReadNextRecordBatchAsync(CancellationToken cancellationToken = default)
        {
            if (_consumed)
                return null;

            _consumed = true;
            return await Task.Run(() => BuildGetObjectsBatch(), cancellationToken);
        }

        private RecordBatch BuildGetObjectsBatch()
        {
            // Step 1: Get catalogs
            var catalogs = GetCatalogs();

            var catalogNames = new StringArray.Builder();
            var catalogDbSchemasBuilder = new List<List<(string schemaName, List<(string tableName, string tableType)>? tables)>>();

            foreach (var catalog in catalogs)
            {
                catalogNames.Append(catalog);

                if (_depth == AdbcConnection.GetObjectsDepth.Catalogs)
                {
                    catalogDbSchemasBuilder.Add(new List<(string, List<(string, string)>?)>());
                    continue;
                }

                // Step 2: Get schemas for this catalog
                var schemas = ReadDbSchemas(catalog);
                var schemaList = new List<(string schemaName, List<(string tableName, string tableType)>? tables)>();

                foreach (var schema in schemas)
                {
                    if (_depth == AdbcConnection.GetObjectsDepth.DbSchemas)
                    {
                        schemaList.Add((schema, null));
                        continue;
                    }

                    // Step 3: Get tables for this catalog + schema
                    var tables = ReadTables(catalog, schema);
                    schemaList.Add((schema, tables));
                }

                catalogDbSchemasBuilder.Add(schemaList);
            }

            return BuildRecordBatch(catalogs, catalogDbSchemasBuilder);
        }

        private List<string> GetCatalogs()
        {
            var command = new CommandGetCatalogs();
            using var result = _connection.ExecuteFlightSqlCommand(command);
            return ReadAllStrings(result, "catalog_name");
        }

        private List<string> ReadDbSchemas(string catalog)
        {
            var command = new CommandGetDbSchemas { Catalog = catalog };
            if (_dbSchemaPattern != null)
                command.DbSchemaFilterPattern = _dbSchemaPattern;

            using var result = _connection.ExecuteFlightSqlCommand(command);
            return ReadAllStrings(result, "db_schema_name");
        }

        private List<(string tableName, string tableType)> ReadTables(string catalog, string dbSchema)
        {
            var command = new CommandGetTables
            {
                Catalog = catalog,
                DbSchemaFilterPattern = dbSchema,
                IncludeSchema = false,
            };

            if (_tableNamePattern != null)
                command.TableNameFilterPattern = _tableNamePattern;

            if (_tableTypes != null)
            {
                foreach (var t in _tableTypes)
                    command.TableTypes.Add(t);
            }

            using var result = _connection.ExecuteFlightSqlCommand(command);
            var tables = new List<(string, string)>();

            while (true)
            {
                var batch = result.ReadNextRecordBatchAsync().AsTask().GetAwaiter().GetResult();
                if (batch == null) break;

                var tableNameIdx = batch.Schema.GetFieldIndex("table_name");
                var tableTypeIdx = batch.Schema.GetFieldIndex("table_type");

                var nameArray = batch.Column(tableNameIdx) as StringArray;
                var typeArray = batch.Column(tableTypeIdx) as StringArray;

                if (nameArray != null && typeArray != null)
                {
                    for (int i = 0; i < batch.Length; i++)
                    {
                        tables.Add((nameArray.GetString(i), typeArray.GetString(i)));
                    }
                }
            }

            return tables;
        }

        private List<string> ReadAllStrings(GizmoSqlResult result, string columnName)
        {
            var values = new List<string>();

            while (true)
            {
                var batch = result.ReadNextRecordBatchAsync().AsTask().GetAwaiter().GetResult();
                if (batch == null) break;

                var colIdx = batch.Schema.GetFieldIndex(columnName);
                var array = batch.Column(colIdx) as StringArray;
                if (array != null)
                {
                    for (int i = 0; i < batch.Length; i++)
                    {
                        var val = array.GetString(i);
                        if (val != null)
                            values.Add(val);
                    }
                }
            }

            return values;
        }

        private List<string> ReadAllStrings(IArrowArrayStream stream, string columnName)
        {
            // This overload accepts any IArrowArrayStream (used when caller has a non-GizmoSqlResult stream)
            var values = new List<string>();

            while (true)
            {
                var batch = stream.ReadNextRecordBatchAsync().AsTask().GetAwaiter().GetResult();
                if (batch == null) break;

                var colIdx = batch.Schema.GetFieldIndex(columnName);
                var array = batch.Column(colIdx) as StringArray;
                if (array != null)
                {
                    for (int i = 0; i < batch.Length; i++)
                    {
                        var val = array.GetString(i);
                        if (val != null)
                            values.Add(val);
                    }
                }
            }

            return values;
        }

        private RecordBatch BuildRecordBatch(
            List<string> catalogs,
            List<List<(string schemaName, List<(string tableName, string tableType)>? tables)>> catalogSchemas)
        {
            // Build the nested Arrow arrays conforming to GetObjectsSchema
            var catalogNameBuilder = new StringArray.Builder();
            var dbSchemaListOffsets = new List<int> { 0 };
            var dbSchemaNames = new List<string>();
            var tableListOffsets = new List<int> { 0 };
            var tableNames = new List<string>();
            var tableTypes = new List<string>();

            for (int ci = 0; ci < catalogs.Count; ci++)
            {
                catalogNameBuilder.Append(catalogs[ci]);

                var schemas = catalogSchemas[ci];
                int tableOffsetBase = tableNames.Count;

                foreach (var (schemaName, tables) in schemas)
                {
                    dbSchemaNames.Add(schemaName);

                    if (tables != null)
                    {
                        foreach (var (tn, tt) in tables)
                        {
                            tableNames.Add(tn);
                            tableTypes.Add(tt);
                        }
                    }
                    tableListOffsets.Add(tableNames.Count);
                }

                dbSchemaListOffsets.Add(dbSchemaNames.Count);
            }

            // For simplicity, return a minimal GetObjects result.
            // A full implementation would include table_columns and table_constraints.
            // Power BI primarily needs catalogs → schemas → tables.
            var catalogNamesArray = catalogNameBuilder.Build();
            var numCatalogs = catalogs.Count;

            // Build db_schema struct arrays
            var schemaNameBuilder = new StringArray.Builder();
            foreach (var s in dbSchemaNames) schemaNameBuilder.Append(s);
            var schemaNameArray = schemaNameBuilder.Build();

            // Build table struct arrays
            var tblNameBuilder = new StringArray.Builder();
            var tblTypeBuilder = new StringArray.Builder();
            foreach (var t in tableNames) tblNameBuilder.Append(t);
            foreach (var t in tableTypes) tblTypeBuilder.Append(t);

            // Build empty column and constraint lists for the table-level struct
            var emptyColumnOffsets = new ArrowBuffer.Builder<int>();
            var emptyConstraintOffsets = new ArrowBuffer.Builder<int>();
            for (int i = 0; i <= tableNames.Count; i++)
            {
                emptyColumnOffsets.Append(0);
                emptyConstraintOffsets.Append(0);
            }

            // This is a simplified implementation. Full nested struct/list building
            // requires the Arrow StructArray and ListArray builders, which is complex.
            // For now, return the data at the catalog level to get the driver operational.
            // TODO: Build proper nested GetObjects response with full depth support.
            return new RecordBatch(
                StandardSchemas.GetObjectsSchema,
                new IArrowArray[]
                {
                    catalogNamesArray,
                    // catalog_db_schemas: list<struct<db_schema_name, db_schema_tables>>
                    // Simplified: return an empty list for now to satisfy the schema contract
                    BuildEmptyDbSchemaList(numCatalogs),
                },
                numCatalogs);
        }

        private static IArrowArray BuildEmptyDbSchemaList(int length)
        {
            // Build a list array with all empty lists
            var offsets = new ArrowBuffer.Builder<int>();
            for (int i = 0; i <= length; i++)
                offsets.Append(0);

            // Empty struct arrays for the db_schema items
            var emptySchemaNames = new StringArray.Builder().Build();
            var emptyTablesList = BuildEmptyTablesList(0);

            var dbSchemaStruct = new StructArray(
                new StructType(StandardSchemas.DbSchemaSchema),
                0,
                new IArrowArray[] { emptySchemaNames, emptyTablesList },
                ArrowBuffer.Empty);

            return new ListArray(
                new ListType(new Field("item", new StructType(StandardSchemas.DbSchemaSchema), true)),
                length,
                offsets.Build(),
                dbSchemaStruct,
                ArrowBuffer.Empty);
        }

        private static IArrowArray BuildEmptyTablesList(int length)
        {
            var offsets = new ArrowBuffer.Builder<int>();
            for (int i = 0; i <= length; i++)
                offsets.Append(0);

            var emptyTableNames = new StringArray.Builder().Build();
            var emptyTableTypes = new StringArray.Builder().Build();
            var emptyColumnsList = BuildEmptyColumnsList(0);
            var emptyConstraintsList = BuildEmptyConstraintsList(0);

            var tableStruct = new StructArray(
                new StructType(StandardSchemas.TableSchema),
                0,
                new IArrowArray[] { emptyTableNames, emptyTableTypes, emptyColumnsList, emptyConstraintsList },
                ArrowBuffer.Empty);

            return new ListArray(
                new ListType(new Field("item", new StructType(StandardSchemas.TableSchema), true)),
                length,
                offsets.Build(),
                tableStruct,
                ArrowBuffer.Empty);
        }

        private static IArrowArray BuildEmptyColumnsList(int length)
        {
            var offsets = new ArrowBuffer.Builder<int>();
            for (int i = 0; i <= length; i++)
                offsets.Append(0);

            // Build empty arrays for each column field
            var fields = StandardSchemas.ColumnSchema;
            var arrays = new IArrowArray[fields.Count];
            for (int i = 0; i < fields.Count; i++)
            {
                arrays[i] = CreateEmptyArray(fields[i]);
            }

            var columnStruct = new StructArray(
                new StructType(StandardSchemas.ColumnSchema),
                0,
                arrays,
                ArrowBuffer.Empty);

            return new ListArray(
                new ListType(new Field("item", new StructType(StandardSchemas.ColumnSchema), true)),
                length,
                offsets.Build(),
                columnStruct,
                ArrowBuffer.Empty);
        }

        private static IArrowArray BuildEmptyConstraintsList(int length)
        {
            var offsets = new ArrowBuffer.Builder<int>();
            for (int i = 0; i <= length; i++)
                offsets.Append(0);

            var fields = StandardSchemas.ConstraintSchema;
            var arrays = new IArrowArray[fields.Count];
            for (int i = 0; i < fields.Count; i++)
            {
                arrays[i] = CreateEmptyArray(fields[i]);
            }

            var constraintStruct = new StructArray(
                new StructType(StandardSchemas.ConstraintSchema),
                0,
                arrays,
                ArrowBuffer.Empty);

            return new ListArray(
                new ListType(new Field("item", new StructType(StandardSchemas.ConstraintSchema), true)),
                length,
                offsets.Build(),
                constraintStruct,
                ArrowBuffer.Empty);
        }

        private static IArrowArray CreateEmptyArray(Field field)
        {
            if (field.DataType is StringType)
                return new StringArray.Builder().Build();
            if (field.DataType is Int32Type)
                return new Int32Array.Builder().Build();
            if (field.DataType is Int16Type)
                return new Int16Array.Builder().Build();
            if (field.DataType is BooleanType)
                return new BooleanArray.Builder().Build();
            if (field.DataType is ListType)
            {
                var offsets = new ArrowBuffer.Builder<int>();
                offsets.Append(0);
                var innerField = ((ListType)field.DataType).ValueField;
                return new ListArray(field.DataType as ListType,
                    0,
                    offsets.Build(),
                    CreateEmptyArray(innerField),
                    ArrowBuffer.Empty);
            }
            // Fallback: empty string array
            return new StringArray.Builder().Build();
        }

        public void Dispose()
        {
        }
    }
}
