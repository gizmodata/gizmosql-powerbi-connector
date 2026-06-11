// Licensed under the Apache License, Version 2.0

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Connection parameter constants for the GizmoSQL ADBC driver.
    /// </summary>
    public static class GizmoSqlParameters
    {
        /// <summary>Full gRPC URI (e.g. "grpc+tls://host:port").</summary>
        public const string ServerAddress = "adbc.gizmosql.server_address";

        /// <summary>Hostname only (alternative to full URI).</summary>
        public const string Host = "adbc.gizmosql.host";

        /// <summary>Port number (default 31337).</summary>
        public const string Port = "adbc.gizmosql.port";

        /// <summary>Username for authentication.</summary>
        public const string Username = "adbc.gizmosql.username";

        /// <summary>Password for authentication.</summary>
        public const string Password = "adbc.gizmosql.password";

        /// <summary>Enable TLS ("true"/"false", default "true").</summary>
        public const string TlsEnabled = "adbc.gizmosql.tls.enabled";

        /// <summary>Skip TLS certificate verification ("true"/"false").</summary>
        public const string TlsSkipVerify = "adbc.gizmosql.tls.skip_verify";

        /// <summary>Auth type: "password", "token", or "external".</summary>
        public const string AuthType = "adbc.gizmosql.auth.type";

        /// <summary>JWT token (for token auth).</summary>
        public const string AuthToken = "adbc.gizmosql.auth.token";

        /// <summary>OAuth server port (default 31339).</summary>
        public const string OAuthPort = "adbc.gizmosql.oauth.port";

        /// <summary>Explicit OAuth base URL.</summary>
        public const string OAuthUrl = "adbc.gizmosql.oauth.url";

        /// <summary>OAuth timeout in seconds (default 300).</summary>
        public const string OAuthTimeout = "adbc.gizmosql.oauth.timeout";

        // Defaults
        public const int DefaultPort = 31337;
        public const int DefaultOAuthPort = 31339;
        public const int DefaultOAuthTimeout = 300;
        public const string DefaultAuthType = "password";
    }
}
