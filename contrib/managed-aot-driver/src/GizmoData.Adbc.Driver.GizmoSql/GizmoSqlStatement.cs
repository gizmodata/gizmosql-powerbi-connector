// Licensed under the Apache License, Version 2.0

using System;
using System.Threading.Tasks;
using Apache.Arrow.Adbc;
using Apache.Arrow.Flight;
using Arrow.Flight.Protocol.Sql;
using Google.Protobuf;
using Google.Protobuf.WellKnownTypes;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// A GizmoSQL implementation of <see cref="AdbcStatement"/>.
    /// Executes SQL queries via Arrow Flight SQL using CommandStatementQuery protobuf commands.
    /// </summary>
    public class GizmoSqlStatement : AdbcStatement
    {
        private readonly GizmoSqlConnection _connection;

        public GizmoSqlStatement(GizmoSqlConnection connection)
        {
            _connection = connection ?? throw new ArgumentNullException(nameof(connection));
        }

        public override QueryResult ExecuteQuery()
        {
            return ExecuteQueryAsync().AsTask().GetAwaiter().GetResult();
        }

        public override async ValueTask<QueryResult> ExecuteQueryAsync()
        {
            if (string.IsNullOrEmpty(SqlQuery))
                throw new InvalidOperationException("SqlQuery must be set before executing.");

            var command = new CommandStatementQuery { Query = SqlQuery! };
            var packed = Any.Pack(command);
            var descriptor = FlightDescriptor.CreateCommandDescriptor(packed.ToByteArray());

            var info = await _connection.FlightClient
                .GetInfo(descriptor, _connection.AuthHeaders)
                .ResponseAsync;

            return new QueryResult(info.TotalRecords, new GizmoSqlResult(_connection, info));
        }

        public override UpdateResult ExecuteUpdate()
        {
            if (string.IsNullOrEmpty(SqlQuery))
                throw new InvalidOperationException("SqlQuery must be set before executing.");

            var command = new CommandStatementQuery { Query = SqlQuery! };
            var packed = Any.Pack(command);
            var descriptor = FlightDescriptor.CreateCommandDescriptor(packed.ToByteArray());

            var info = _connection.FlightClient
                .GetInfo(descriptor, _connection.AuthHeaders)
                .ResponseAsync.GetAwaiter().GetResult();

            long affectedRows = 0;
            using var result = new GizmoSqlResult(_connection, info);

            while (true)
            {
                var batch = result.ReadNextRecordBatchAsync().AsTask().GetAwaiter().GetResult();
                if (batch == null)
                    break;
                affectedRows += batch.Length;
            }

            return new UpdateResult(affectedRows);
        }
    }
}
