// Licensed under the Apache License, Version 2.0

using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    public class TlsHelperTests
    {
        [Fact]
        public void CreateChannelOptions_WithSkipVerify_ReturnsOptions()
        {
            var options = GizmoSqlTlsHelper.CreateChannelOptions(skipVerify: true);
            Assert.NotNull(options);
            Assert.NotNull(options.HttpHandler);
        }

        [Fact]
        public void CreateChannelOptions_WithoutSkipVerify_ReturnsOptions()
        {
            var options = GizmoSqlTlsHelper.CreateChannelOptions(skipVerify: false);
            Assert.NotNull(options);
            Assert.NotNull(options.HttpHandler);
        }

        [Fact]
        public void CreateChannelOptions_UnlimitedMessageSize()
        {
            var options = GizmoSqlTlsHelper.CreateChannelOptions(skipVerify: false);
            Assert.Null(options.MaxReceiveMessageSize);
        }
    }
}
