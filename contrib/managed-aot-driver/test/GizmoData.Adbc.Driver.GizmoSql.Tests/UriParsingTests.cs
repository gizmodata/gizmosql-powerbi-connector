// Licensed under the Apache License, Version 2.0

using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class UriParsingTests
    {
        [Theory]
        [InlineData("grpc+tls://localhost:31337", "https://localhost:31337")]
        [InlineData("grpc+tls://myhost:443", "https://myhost:443")]
        [InlineData("grpc://localhost:31337", "http://localhost:31337")]
        [InlineData("grpc+tcp://localhost:31337", "http://localhost:31337")]
        [InlineData("https://already-https:8080", "https://already-https:8080")]
        [InlineData("http://already-http:8080", "http://already-http:8080")]
        public void ConvertFlightUri_ConvertsCorrectly(string input, string expected)
        {
            var result = GizmoSqlConnection.ConvertFlightUri(input);
            Assert.Equal(expected, result);
        }

        [Fact]
        public void ConvertFlightUri_UnsupportedScheme_Throws()
        {
            Assert.Throws<System.ArgumentException>(() =>
                GizmoSqlConnection.ConvertFlightUri("ftp://host:123"));
        }

        [Theory]
        [InlineData("grpc+tls://myhost:31337", "myhost")]
        [InlineData("grpc://myhost:31337", "myhost")]
        [InlineData("grpc+tcp://myhost:31337", "myhost")]
        [InlineData("https://myhost:31337", "myhost")]
        [InlineData("grpc+tls://myhost:31337/", "myhost")]
        public void ExtractHost_ExtractsCorrectly(string input, string expected)
        {
            var result = GizmoSqlConnection.ExtractHost(input);
            Assert.Equal(expected, result);
        }

        [Fact]
        public void ResolveGrpcUri_FromServerAddress()
        {
            var parameters = new System.Collections.Generic.Dictionary<string, string>
            {
                [GizmoSqlParameters.ServerAddress] = "grpc+tls://myserver:31337",
            };

            var connection = new GizmoSqlConnection(parameters);
            var uri = connection.ResolveGrpcUri();
            Assert.Equal("https://myserver:31337", uri);
        }

        [Fact]
        public void ResolveGrpcUri_FromHostAndPort()
        {
            var parameters = new System.Collections.Generic.Dictionary<string, string>
            {
                [GizmoSqlParameters.Host] = "myserver",
                [GizmoSqlParameters.Port] = "9090",
            };

            var connection = new GizmoSqlConnection(parameters);
            var uri = connection.ResolveGrpcUri();
            Assert.Equal("https://myserver:9090", uri);
        }

        [Fact]
        public void ResolveGrpcUri_FromHostWithTlsDisabled()
        {
            var parameters = new System.Collections.Generic.Dictionary<string, string>
            {
                [GizmoSqlParameters.Host] = "myserver",
                [GizmoSqlParameters.TlsEnabled] = "false",
            };

            var connection = new GizmoSqlConnection(parameters);
            var uri = connection.ResolveGrpcUri();
            Assert.Equal("http://myserver:31337", uri);
        }

        [Fact]
        public void ResolveGrpcUri_DefaultPort()
        {
            var parameters = new System.Collections.Generic.Dictionary<string, string>
            {
                [GizmoSqlParameters.Host] = "myserver",
            };

            var connection = new GizmoSqlConnection(parameters);
            var uri = connection.ResolveGrpcUri();
            Assert.Equal("https://myserver:31337", uri);
        }

        [Fact]
        public void ResolveGrpcUri_NoHostOrUri_Throws()
        {
            var parameters = new System.Collections.Generic.Dictionary<string, string>();

            var connection = new GizmoSqlConnection(parameters);
            Assert.Throws<System.ArgumentException>(() => connection.ResolveGrpcUri());
        }
    }
}
