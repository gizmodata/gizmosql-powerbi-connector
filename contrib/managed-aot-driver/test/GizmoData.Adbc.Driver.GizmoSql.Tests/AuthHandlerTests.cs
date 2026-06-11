// Licensed under the Apache License, Version 2.0

using System;
using System.Text;
using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class AuthHandlerTests
    {
        [Fact]
        public void CreateBasicAuthHeaderValue_EncodesCorrectly()
        {
            var result = GizmoSqlAuthHandler.CreateBasicAuthHeaderValue("user", "pass");

            var expected = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes("user:pass"));
            Assert.Equal(expected, result);
        }

        [Fact]
        public void CreateAuthMetadata_PasswordAuth_SetsHeader()
        {
            var metadata = GizmoSqlAuthHandler.CreateAuthMetadata("password", "admin", "secret", null);

            Assert.Single(metadata);
            var entry = metadata[0];
            Assert.Equal("authorization", entry.Key);

            var expected = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes("admin:secret"));
            Assert.Equal(expected, entry.Value);
        }

        [Fact]
        public void CreateAuthMetadata_TokenAuth_UsesTokenAsPassword()
        {
            var jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test";
            var metadata = GizmoSqlAuthHandler.CreateAuthMetadata("token", null, null, jwt);

            Assert.Single(metadata);
            var entry = metadata[0];
            Assert.Equal("authorization", entry.Key);

            var expected = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes($"token:{jwt}"));
            Assert.Equal(expected, entry.Value);
        }

        [Fact]
        public void CreateAuthMetadata_ExternalAuth_UsesTokenAsPassword()
        {
            var jwt = "my-jwt-token";
            var metadata = GizmoSqlAuthHandler.CreateAuthMetadata("external", null, null, jwt);

            Assert.Single(metadata);
            var entry = metadata[0];
            Assert.Equal("authorization", entry.Key);

            var expected = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes($"token:{jwt}"));
            Assert.Equal(expected, entry.Value);
        }

        [Fact]
        public void CreateAuthMetadata_NoCredentials_EmptyMetadata()
        {
            var metadata = GizmoSqlAuthHandler.CreateAuthMetadata("password", null, null, null);
            Assert.Empty(metadata);
        }

        [Fact]
        public void CreateAuthMetadata_CaseInsensitive()
        {
            var metadata = GizmoSqlAuthHandler.CreateAuthMetadata("PASSWORD", "user", "pass", null);
            Assert.Single(metadata);
        }
    }
}
