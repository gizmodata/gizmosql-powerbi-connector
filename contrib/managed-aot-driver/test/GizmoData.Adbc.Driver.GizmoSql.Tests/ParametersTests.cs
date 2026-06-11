// Licensed under the Apache License, Version 2.0

using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class ParametersTests
    {
        [Fact]
        public void Constants_HaveCorrectValues()
        {
            Assert.Equal("adbc.gizmosql.server_address", GizmoSqlParameters.ServerAddress);
            Assert.Equal("adbc.gizmosql.host", GizmoSqlParameters.Host);
            Assert.Equal("adbc.gizmosql.port", GizmoSqlParameters.Port);
            Assert.Equal("adbc.gizmosql.username", GizmoSqlParameters.Username);
            Assert.Equal("adbc.gizmosql.password", GizmoSqlParameters.Password);
            Assert.Equal("adbc.gizmosql.tls.enabled", GizmoSqlParameters.TlsEnabled);
            Assert.Equal("adbc.gizmosql.tls.skip_verify", GizmoSqlParameters.TlsSkipVerify);
            Assert.Equal("adbc.gizmosql.auth.type", GizmoSqlParameters.AuthType);
            Assert.Equal("adbc.gizmosql.auth.token", GizmoSqlParameters.AuthToken);
            Assert.Equal("adbc.gizmosql.oauth.port", GizmoSqlParameters.OAuthPort);
            Assert.Equal("adbc.gizmosql.oauth.url", GizmoSqlParameters.OAuthUrl);
            Assert.Equal("adbc.gizmosql.oauth.timeout", GizmoSqlParameters.OAuthTimeout);
        }

        [Fact]
        public void Defaults_HaveCorrectValues()
        {
            Assert.Equal(31337, GizmoSqlParameters.DefaultPort);
            Assert.Equal(31339, GizmoSqlParameters.DefaultOAuthPort);
            Assert.Equal(300, GizmoSqlParameters.DefaultOAuthTimeout);
            Assert.Equal("password", GizmoSqlParameters.DefaultAuthType);
        }
    }
}
