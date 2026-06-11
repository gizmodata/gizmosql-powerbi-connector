// Licensed under the Apache License, Version 2.0

using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Apache.Arrow.Adbc;
using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    /// <summary>
    /// Integration tests that require a running GizmoSQL server.
    /// Start with: docker run -p 31337:31337 gizmodata/gizmosql:latest
    ///
    /// These tests are skipped unless the GIZMOSQL_TEST_HOST environment variable is set.
    /// </summary>
    [Collection("Integration")]
    public class IntegrationTests
    {
        private readonly string? _host;
        private readonly bool _tlsSkipVerify;
        private readonly string? _username;
        private readonly string? _password;

        public IntegrationTests()
        {
            _host = Environment.GetEnvironmentVariable("GIZMOSQL_TEST_HOST");
            _tlsSkipVerify = string.Equals(
                Environment.GetEnvironmentVariable("GIZMOSQL_TEST_TLS_SKIP_VERIFY"),
                "true", StringComparison.OrdinalIgnoreCase);
            _username = Environment.GetEnvironmentVariable("GIZMOSQL_TEST_USERNAME");
            _password = Environment.GetEnvironmentVariable("GIZMOSQL_TEST_PASSWORD");
        }

        private bool CanRun => !string.IsNullOrEmpty(_host);

        private AdbcConnection CreateConnection()
        {
            var parameters = new Dictionary<string, string>
            {
                [GizmoSqlParameters.ServerAddress] = _host!,
            };

            if (_tlsSkipVerify)
                parameters[GizmoSqlParameters.TlsSkipVerify] = "true";

            if (!string.IsNullOrEmpty(_username))
                parameters[GizmoSqlParameters.Username] = _username!;

            if (!string.IsNullOrEmpty(_password))
                parameters[GizmoSqlParameters.Password] = _password!;

            var driver = new GizmoSqlDriver();
            var database = driver.Open((IReadOnlyDictionary<string, string>)parameters);
            return database.Connect(null);
        }

        [Fact]
        public async Task Connect_And_ExecuteQuery()
        {
            if (!CanRun)
            {
                return; // Skip: GIZMOSQL_TEST_HOST not set
            }

            using var connection = CreateConnection();
            using var statement = connection.CreateStatement();
            statement.SqlQuery = "SELECT 1 AS value";

            var result = statement.ExecuteQuery();
            Assert.NotNull(result.Stream);

            var batch = await result.Stream.ReadNextRecordBatchAsync();
            Assert.NotNull(batch);
            Assert.Equal(1, batch!.Length);
        }

        [Fact]
        public async Task GetTableTypes_ReturnsResults()
        {
            if (!CanRun)
            {
                return; // Skip: GIZMOSQL_TEST_HOST not set
            }

            using var connection = CreateConnection();
            using var stream = connection.GetTableTypes();

            var batch = await stream.ReadNextRecordBatchAsync();
            Assert.NotNull(batch);
            Assert.True(batch!.Length > 0);
        }

        [Fact]
        public async Task GetObjects_Catalogs_ReturnsResults()
        {
            if (!CanRun)
            {
                return; // Skip: GIZMOSQL_TEST_HOST not set
            }

            using var connection = CreateConnection();
            using var stream = connection.GetObjects(
                AdbcConnection.GetObjectsDepth.Catalogs,
                null, null, null, null, null);

            var batch = await stream.ReadNextRecordBatchAsync();
            Assert.NotNull(batch);
        }

        [Fact]
        public async Task GetInfo_ReturnsDriverMetadata()
        {
            if (!CanRun)
            {
                return; // Skip: GIZMOSQL_TEST_HOST not set
            }

            using var connection = CreateConnection();
            var codes = new List<AdbcInfoCode>
            {
                AdbcInfoCode.DriverName,
                AdbcInfoCode.VendorName,
            };

            using var stream = connection.GetInfo(codes);
            var batch = await stream.ReadNextRecordBatchAsync();
            Assert.NotNull(batch);
            Assert.Equal(2, batch!.Length);
        }
    }
}
