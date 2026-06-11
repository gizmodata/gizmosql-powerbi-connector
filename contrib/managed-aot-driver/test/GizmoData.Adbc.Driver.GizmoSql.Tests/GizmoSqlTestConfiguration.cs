// Licensed under the Apache License, Version 2.0

using System;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    /// <summary>
    /// Test configuration loaded from environment variables.
    /// </summary>
    public static class GizmoSqlTestConfiguration
    {
        /// <summary>
        /// GizmoSQL server address for integration tests (e.g. "grpc+tls://localhost:31337").
        /// Set GIZMOSQL_TEST_HOST environment variable.
        /// </summary>
        public static string? Host => Environment.GetEnvironmentVariable("GIZMOSQL_TEST_HOST");

        /// <summary>
        /// Whether to skip TLS verification. Set GIZMOSQL_TEST_TLS_SKIP_VERIFY=true.
        /// </summary>
        public static bool TlsSkipVerify => string.Equals(
            Environment.GetEnvironmentVariable("GIZMOSQL_TEST_TLS_SKIP_VERIFY"),
            "true", StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// Username for authentication. Set GIZMOSQL_TEST_USERNAME.
        /// </summary>
        public static string? Username => Environment.GetEnvironmentVariable("GIZMOSQL_TEST_USERNAME");

        /// <summary>
        /// Password for authentication. Set GIZMOSQL_TEST_PASSWORD.
        /// </summary>
        public static string? Password => Environment.GetEnvironmentVariable("GIZMOSQL_TEST_PASSWORD");

        /// <summary>
        /// Whether integration tests can run (requires GIZMOSQL_TEST_HOST).
        /// </summary>
        public static bool CanRunIntegrationTests => !string.IsNullOrEmpty(Host);
    }
}
