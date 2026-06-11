// Licensed under the Apache License, Version 2.0

using System;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class OAuthFlowTests
    {
        [Fact]
        public void OAuthResult_StoresValues()
        {
            var result = new OAuthResult("my-token", "my-uuid");
            Assert.Equal("my-token", result.Token);
            Assert.Equal("my-uuid", result.SessionUuid);
        }

        [Fact]
        public void GizmoSqlOAuthException_Message()
        {
            var ex = new GizmoSqlOAuthException("test error");
            Assert.Equal("test error", ex.Message);
        }

        [Fact]
        public void GizmoSqlOAuthException_InnerException()
        {
            var inner = new InvalidOperationException("inner");
            var ex = new GizmoSqlOAuthException("outer", inner);
            Assert.Equal("outer", ex.Message);
            Assert.Same(inner, ex.InnerException);
        }

        [Fact]
        public async Task GetOAuthTokenAsync_InvalidHost_ThrowsOAuthException()
        {
            // Attempting to connect to a non-existent host should fail with an OAuth exception
            await Assert.ThrowsAsync<GizmoSqlOAuthException>(async () =>
            {
                await GizmoSqlOAuthFlow.GetOAuthTokenAsync(
                    host: "nonexistent.invalid.host.test",
                    port: 99999,
                    tlsSkipVerify: true,
                    timeoutSeconds: 5);
            });
        }
    }
}
