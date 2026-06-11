// Licensed under the Apache License, Version 2.0

using System.Collections.Generic;
using System.Threading.Tasks;
using Apache.Arrow.Adbc;
using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class DriverTests
    {
        [Fact]
        public void Driver_Open_ReturnsDatabase()
        {
            var driver = new GizmoSqlDriver();
            IReadOnlyDictionary<string, string> parameters = new Dictionary<string, string>
            {
                [GizmoSqlParameters.ServerAddress] = "grpc+tls://localhost:31337",
            };
            var database = driver.Open(parameters);

            Assert.NotNull(database);
            Assert.IsType<GizmoSqlDatabase>(database);
        }

        [Fact]
        public void Driver_Open_NullParameters_ReturnsDatabase()
        {
            var driver = new GizmoSqlDriver();
            var database = driver.Open((IReadOnlyDictionary<string, string>?)null);

            Assert.NotNull(database);
            Assert.IsType<GizmoSqlDatabase>(database);
        }

        [Fact]
        public void Database_Connect_MergesParameters()
        {
            var driver = new GizmoSqlDriver();
            IReadOnlyDictionary<string, string> parameters = new Dictionary<string, string>
            {
                [GizmoSqlParameters.Host] = "myserver",
                [GizmoSqlParameters.Username] = "admin",
            };
            var database = driver.Open(parameters);

            Assert.NotNull(database);
        }

        [Fact]
        public async Task GetInfo_ReturnsStream()
        {
            var parameters = new Dictionary<string, string>
            {
                [GizmoSqlParameters.Host] = "localhost",
            };
            var connection = new GizmoSqlConnection(parameters);

            var codes = new List<AdbcInfoCode>
            {
                AdbcInfoCode.DriverName,
                AdbcInfoCode.DriverVersion,
                AdbcInfoCode.VendorName,
                AdbcInfoCode.VendorSql,
            };

            using var stream = connection.GetInfo(codes);
            Assert.NotNull(stream);
            Assert.NotNull(stream.Schema);

            var batch = await stream.ReadNextRecordBatchAsync();
            Assert.NotNull(batch);
            Assert.Equal(4, batch!.Length);
        }
    }
}
