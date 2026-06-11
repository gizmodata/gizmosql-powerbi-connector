// Licensed under the Apache License, Version 2.0

using System;
using System.Collections.Generic;
using Apache.Arrow;
using Apache.Arrow.Adbc;
using Apache.Arrow.Flight;
using Apache.Arrow.Flight.Client;
using Apache.Arrow.Ipc;
using Arrow.Flight.Protocol.Sql;
using Google.Protobuf;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using Grpc.Net.Client;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// A GizmoSQL implementation of <see cref="AdbcConnection"/>.
    /// Manages FlightClient lifecycle, authentication, and metadata queries
    /// using Flight SQL protocol commands.
    /// </summary>
    public class GizmoSqlConnection : AdbcConnection
    {
        private readonly IReadOnlyDictionary<string, string> _parameters;
        private FlightClient? _flightClient;
        private GrpcChannel? _channel;
        private Metadata? _authHeaders;

        public GizmoSqlConnection(IReadOnlyDictionary<string, string> parameters)
        {
            _parameters = parameters ?? throw new ArgumentNullException(nameof(parameters));
        }

        internal FlightClient FlightClient =>
            _flightClient ?? throw new InvalidOperationException("Connection is not open. Call Open() first.");

        internal Metadata AuthHeaders =>
            _authHeaders ?? new Metadata();

        /// <summary>
        /// Opens the connection to the GizmoSQL server.
        /// Establishes the gRPC channel, creates a FlightClient, and performs
        /// a Handshake RPC to authenticate and obtain a bearer token.
        /// </summary>
        public void Open()
        {
            var grpcUri = ResolveGrpcUri();
            var skipVerify = GetBoolParam(GizmoSqlParameters.TlsSkipVerify, false);

            // Create gRPC channel with TLS configuration
            var channelOptions = GizmoSqlTlsHelper.CreateChannelOptions(skipVerify);
            _channel = GrpcChannel.ForAddress(grpcUri, channelOptions);
            _flightClient = new FlightClient(_channel);

            // Authenticate via Flight Handshake RPC
            _authHeaders = PerformHandshake();
        }

        /// <summary>
        /// Resolves the gRPC URI from connection parameters.
        /// Handles both full URI ("grpc+tls://host:port") and component-based (host + port + tls.enabled).
        /// </summary>
        internal string ResolveGrpcUri()
        {
            // Option 1: Full URI provided
            if (_parameters.TryGetValue(GizmoSqlParameters.ServerAddress, out var serverAddress) &&
                !string.IsNullOrWhiteSpace(serverAddress))
            {
                return ConvertFlightUri(serverAddress);
            }

            // Option 2: Build from host + port + tls.enabled
            if (_parameters.TryGetValue(GizmoSqlParameters.Host, out var host) &&
                !string.IsNullOrWhiteSpace(host))
            {
                var port = GetIntParam(GizmoSqlParameters.Port, GizmoSqlParameters.DefaultPort);
                var tlsEnabled = GetBoolParam(GizmoSqlParameters.TlsEnabled, true);
                var scheme = tlsEnabled ? "https" : "http";
                return $"{scheme}://{host}:{port}";
            }

            throw new ArgumentException(
                $"Connection parameters must include either '{GizmoSqlParameters.ServerAddress}' " +
                $"or '{GizmoSqlParameters.Host}'.");
        }

        /// <summary>
        /// Converts a Flight SQL URI to a gRPC URI.
        /// "grpc+tls://host:port" → "https://host:port"
        /// "grpc://host:port" → "http://host:port"
        /// "grpc+tcp://host:port" → "http://host:port"
        /// </summary>
        internal static string ConvertFlightUri(string uri)
        {
            if (uri.StartsWith("grpc+tls://", StringComparison.OrdinalIgnoreCase))
            {
                return "https://" + uri.Substring("grpc+tls://".Length);
            }

            if (uri.StartsWith("grpc+tcp://", StringComparison.OrdinalIgnoreCase))
            {
                return "http://" + uri.Substring("grpc+tcp://".Length);
            }

            if (uri.StartsWith("grpc://", StringComparison.OrdinalIgnoreCase))
            {
                return "http://" + uri.Substring("grpc://".Length);
            }

            // If already http(s), return as-is
            if (uri.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return uri;
            }

            throw new ArgumentException($"Unsupported URI scheme: {uri}");
        }

        /// <summary>
        /// Extracts the hostname from a Flight SQL URI (for OAuth discovery).
        /// </summary>
        internal static string ExtractHost(string uri)
        {
            // Remove scheme
            var remainder = uri;
            var schemeEnd = uri.IndexOf("://", StringComparison.Ordinal);
            if (schemeEnd >= 0)
            {
                remainder = uri.Substring(schemeEnd + 3);
            }

            // Remove port
            var colonIdx = remainder.LastIndexOf(':');
            if (colonIdx >= 0)
            {
                remainder = remainder.Substring(0, colonIdx);
            }

            return remainder.TrimEnd('/');
        }

        /// <summary>
        /// Performs a Flight Handshake RPC to authenticate and obtain a bearer token.
        /// GizmoSQL uses gRPC metadata header-based auth: the client sends
        /// "authorization: Basic ..." in the gRPC metadata, and the server's middleware
        /// returns "authorization: Bearer &lt;jwt&gt;" in the response headers.
        /// The Bearer JWT must be used for all subsequent calls.
        /// </summary>
        private Metadata PerformHandshake()
        {
            var authType = GetStringParam(GizmoSqlParameters.AuthType, GizmoSqlParameters.DefaultAuthType)
                ?? GizmoSqlParameters.DefaultAuthType;
            var username = GetStringParam(GizmoSqlParameters.Username, null);
            var password = GetStringParam(GizmoSqlParameters.Password, null);
            var token = GetStringParam(GizmoSqlParameters.AuthToken, null);

            if (string.Equals(authType, "external", StringComparison.OrdinalIgnoreCase))
            {
                // Run OAuth browser flow to get a JWT token
                var serverAddress = GetStringParam(GizmoSqlParameters.ServerAddress, null);
                var host = GetStringParam(GizmoSqlParameters.Host, null);

                if (host == null && serverAddress != null)
                    host = ExtractHost(serverAddress);

                if (host == null)
                    throw new ArgumentException(
                        "OAuth requires a host. Provide either " +
                        $"'{GizmoSqlParameters.ServerAddress}' or '{GizmoSqlParameters.Host}'.");

                var oauthPort = GetIntParam(GizmoSqlParameters.OAuthPort, GizmoSqlParameters.DefaultOAuthPort);
                var oauthTimeout = GetIntParam(GizmoSqlParameters.OAuthTimeout, GizmoSqlParameters.DefaultOAuthTimeout);
                var oauthUrl = GetStringParam(GizmoSqlParameters.OAuthUrl, null);
                var tlsSkipVerify = GetBoolParam(GizmoSqlParameters.TlsSkipVerify, false);

                var result = GizmoSqlOAuthFlow.GetOAuthToken(host, oauthPort, tlsSkipVerify, oauthTimeout, oauthUrl);
                // OAuth token is used as: username="token", password=<jwt>
                username = "token";
                password = result.Token;
            }
            else if (string.Equals(authType, "token", StringComparison.OrdinalIgnoreCase))
            {
                username = "token";
                password = token;
            }

            // If no credentials, return empty metadata (anonymous)
            if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
            {
                return new Metadata();
            }

            // GizmoSQL uses gRPC middleware-based auth: send Basic auth in the
            // authorization header, and the server's middleware returns a Bearer JWT
            // in the response headers. We use a lightweight GetFlightInfo call
            // (CommandGetTableTypes) to perform the auth exchange, since GizmoSQL
            // does not implement the Handshake RPC.
            var basicAuthValue = GizmoSqlAuthHandler.CreateBasicAuthHeaderValue(username!, password!);
            var basicHeaders = new Metadata { { "authorization", basicAuthValue } };

            // Make a lightweight Flight SQL call with Basic auth to get the Bearer token
            var command = new CommandGetTableTypes();
            var packed = Any.Pack(command);
            var descriptor = FlightDescriptor.CreateCommandDescriptor(packed.ToByteArray());

            var call = _flightClient!.GetInfo(descriptor, basicHeaders);
            // Complete the call to trigger the server's auth middleware
            call.ResponseAsync.GetAwaiter().GetResult();

            // Extract the Bearer token from gRPC response headers
            var responseHeaders = call.ResponseHeadersAsync.GetAwaiter().GetResult();
            var metadata = new Metadata();

            foreach (var entry in responseHeaders)
            {
                if (string.Equals(entry.Key, "authorization", StringComparison.OrdinalIgnoreCase))
                {
                    metadata.Add("authorization", entry.Value);
                    return metadata;
                }
            }

            return metadata;
        }

        public override AdbcStatement CreateStatement()
        {
            return new GizmoSqlStatement(this);
        }

        // --- Metadata methods using Flight SQL protocol commands ---

        /// <summary>
        /// Gets the list of table types supported by the database.
        /// Uses the Flight SQL CommandGetTableTypes protocol command.
        /// </summary>
        public override IArrowArrayStream GetTableTypes()
        {
            var command = new CommandGetTableTypes();
            return ExecuteFlightSqlCommand(command);
        }

        /// <summary>
        /// Gets the Arrow schema of a database table.
        /// Uses the Flight SQL CommandGetTables with include_schema=true.
        /// </summary>
        public override Schema GetTableSchema(string? catalog, string? dbSchema, string tableName)
        {
            var command = new CommandGetTables
            {
                IncludeSchema = true,
                TableNameFilterPattern = tableName,
            };

            if (catalog != null)
                command.Catalog = catalog;
            if (dbSchema != null)
                command.DbSchemaFilterPattern = dbSchema;

            // Execute and read the result to extract the schema
            using var stream = ExecuteFlightSqlCommand(command);
            var schema = stream.Schema;

            // The table_schema column contains the serialized IPC schema bytes.
            // We need to read the first batch and extract the schema from the table_schema column.
            var batch = stream.ReadNextRecordBatchAsync().AsTask().GetAwaiter().GetResult();
            if (batch == null || batch.Length == 0)
            {
                throw new InvalidOperationException(
                    $"Table not found: {(catalog != null ? catalog + "." : "")}" +
                    $"{(dbSchema != null ? dbSchema + "." : "")}{tableName}");
            }

            // Find the table_schema column (binary column with serialized Arrow schema)
            var tableSchemaColIdx = -1;
            for (int i = 0; i < schema.FieldsList.Count; i++)
            {
                if (schema.FieldsList[i].Name == "table_schema")
                {
                    tableSchemaColIdx = i;
                    break;
                }
            }

            if (tableSchemaColIdx < 0)
            {
                throw new InvalidOperationException(
                    "Server did not return table_schema column. " +
                    "Ensure the server supports CommandGetTables with include_schema=true.");
            }

            var schemaArray = batch.Column(tableSchemaColIdx) as Apache.Arrow.BinaryArray;
            if (schemaArray == null || schemaArray.IsNull(0))
            {
                throw new InvalidOperationException("table_schema column is null or not a binary array.");
            }

            var schemaBytes = schemaArray.GetBytes(0).ToArray();
            return FlightSqlSchemaHelper.DeserializeSchema(schemaBytes);
        }

        /// <summary>
        /// Gets a hierarchical view of all catalogs, database schemas, tables, and columns.
        /// </summary>
        public override IArrowArrayStream GetObjects(
            GetObjectsDepth depth,
            string? catalogPattern,
            string? dbSchemaPattern,
            string? tableNamePattern,
            IReadOnlyList<string>? tableTypes,
            string? columnNamePattern)
        {
            // For GetObjects, we use a combination of Flight SQL metadata commands
            // and build the hierarchical structure expected by ADBC.
            // The implementation assembles data from GetCatalogs, GetDbSchemas, GetTables.
            return new GizmoSqlGetObjectsResult(this, depth, catalogPattern, dbSchemaPattern,
                tableNamePattern, tableTypes, columnNamePattern);
        }

        /// <summary>
        /// Gets driver/database metadata.
        /// </summary>
        public override IArrowArrayStream GetInfo(IReadOnlyList<AdbcInfoCode> codes)
        {
            return new GizmoSqlInfoResult(codes);
        }

        // --- Internal helpers ---

        /// <summary>
        /// Executes a Flight SQL protobuf command by packing it into a FlightDescriptor
        /// and calling GetFlightInfo → DoGet.
        /// </summary>
        internal GizmoSqlResult ExecuteFlightSqlCommand(IMessage command)
        {
            var packed = Any.Pack(command);
            var bytes = packed.ToByteArray();
            var descriptor = FlightDescriptor.CreateCommandDescriptor(bytes);

            var info = FlightClient.GetInfo(descriptor, AuthHeaders).ResponseAsync
                .GetAwaiter().GetResult();

            return new GizmoSqlResult(this, info);
        }

        private string? GetStringParam(string key, string? defaultValue)
        {
            return _parameters.TryGetValue(key, out var value) ? value : defaultValue;
        }

        private int GetIntParam(string key, int defaultValue)
        {
            if (_parameters.TryGetValue(key, out var value) && int.TryParse(value, out var result))
                return result;
            return defaultValue;
        }

        private bool GetBoolParam(string key, bool defaultValue)
        {
            if (_parameters.TryGetValue(key, out var value))
            {
                return string.Equals(value, "true", StringComparison.OrdinalIgnoreCase) ||
                       string.Equals(value, "1", StringComparison.OrdinalIgnoreCase);
            }
            return defaultValue;
        }

        public override void Dispose()
        {
            _flightClient = null;
            _channel?.Dispose();
            _channel = null;
            base.Dispose();
        }
    }
}
