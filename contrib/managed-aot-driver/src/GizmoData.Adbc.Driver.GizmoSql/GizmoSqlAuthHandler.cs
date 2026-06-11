// Licensed under the Apache License, Version 2.0

using System;
using System.IO;
using System.Text;
using Google.Protobuf;
using Grpc.Core;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Generates gRPC authentication headers for GizmoSQL connections.
    /// </summary>
    internal static class GizmoSqlAuthHandler
    {
        /// <summary>
        /// Creates a Basic Auth header value: "Basic base64(username:password)".
        /// </summary>
        public static string CreateBasicAuthHeaderValue(string username, string password)
        {
            var credentials = $"{username}:{password}";
            var encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(credentials));
            return $"Basic {encoded}";
        }

        /// <summary>
        /// Serializes a BasicAuth protobuf message (username + password) into bytes
        /// for use with the Flight Handshake RPC.
        /// BasicAuth proto: field 2 = username (string), field 3 = password (string).
        /// </summary>
        public static byte[] SerializeBasicAuth(string username, string password)
        {
            using var stream = new MemoryStream();
            var output = new CodedOutputStream(stream);

            if (!string.IsNullOrEmpty(username))
            {
                output.WriteRawTag(18); // field 2, wire type 2 (length-delimited)
                output.WriteString(username);
            }

            if (!string.IsNullOrEmpty(password))
            {
                output.WriteRawTag(26); // field 3, wire type 2 (length-delimited)
                output.WriteString(password);
            }

            output.Flush();
            return stream.ToArray();
        }

        /// <summary>
        /// Creates gRPC <see cref="Metadata"/> with the authorization header set.
        /// </summary>
        public static Metadata CreateAuthMetadata(string authType, string? username, string? password, string? token)
        {
            var metadata = new Metadata();

            switch (authType.ToLowerInvariant())
            {
                case "password":
                    if (!string.IsNullOrEmpty(username) && !string.IsNullOrEmpty(password))
                    {
                        metadata.Add("authorization", CreateBasicAuthHeaderValue(username!, password!));
                    }
                    break;

                case "token":
                    if (!string.IsNullOrEmpty(token))
                    {
                        metadata.Add("authorization", CreateBasicAuthHeaderValue("token", token!));
                    }
                    break;

                case "external":
                    if (!string.IsNullOrEmpty(token))
                    {
                        metadata.Add("authorization", CreateBasicAuthHeaderValue("token", token!));
                    }
                    break;
            }

            return metadata;
        }
    }
}
