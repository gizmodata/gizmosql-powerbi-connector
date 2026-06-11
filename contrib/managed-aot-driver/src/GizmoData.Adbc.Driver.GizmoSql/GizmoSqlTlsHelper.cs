// Licensed under the Apache License, Version 2.0

using System;
using System.Net.Http;
using System.Threading;
using Grpc.Net.Client;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Builds <see cref="GrpcChannelOptions"/> with appropriate TLS and HTTP handler
    /// configuration for the target framework.
    /// </summary>
    internal static class GizmoSqlTlsHelper
    {
        /// <summary>
        /// Creates gRPC channel options with TLS configuration.
        /// </summary>
        /// <param name="skipVerify">If true, skip TLS certificate verification.</param>
        public static GrpcChannelOptions CreateChannelOptions(bool skipVerify)
        {
#if NETSTANDARD
            // netstandard2.0: use WinHttpHandler (required for gRPC on .NET Framework / Power BI Desktop)
            var handler = new System.Net.Http.WinHttpHandler
            {
                ReceiveDataTimeout = TimeSpan.FromMinutes(5),
                SendTimeout = TimeSpan.FromMinutes(5),
                ReceiveHeadersTimeout = TimeSpan.FromMinutes(5),
            };

            if (skipVerify)
            {
                handler.ServerCertificateValidationCallback = (message, cert, chain, errors) => true;
            }

            return new GrpcChannelOptions
            {
                HttpHandler = handler,
                MaxReceiveMessageSize = null, // unlimited
                DisposeHttpClient = true,
            };
#else
            // net8.0+: use SocketsHttpHandler
            var handler = new SocketsHttpHandler
            {
                PooledConnectionIdleTimeout = Timeout.InfiniteTimeSpan,
                KeepAlivePingDelay = TimeSpan.FromSeconds(60),
                KeepAlivePingTimeout = TimeSpan.FromSeconds(30),
                EnableMultipleHttp2Connections = true,
            };

            if (skipVerify)
            {
                handler.SslOptions = new System.Net.Security.SslClientAuthenticationOptions
                {
                    RemoteCertificateValidationCallback = (sender, certificate, chain, errors) => true,
                };
            }

            return new GrpcChannelOptions
            {
                HttpHandler = handler,
                MaxReceiveMessageSize = null, // unlimited
                DisposeHttpClient = true,
            };
#endif
        }
    }
}
