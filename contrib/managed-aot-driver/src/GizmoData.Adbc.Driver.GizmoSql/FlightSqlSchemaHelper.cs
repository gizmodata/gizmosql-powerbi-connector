// Licensed under the Apache License, Version 2.0

using System.IO;
using Apache.Arrow;
using Apache.Arrow.Ipc;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Helper for deserializing Arrow schemas from IPC-serialized bytes
    /// (as returned by Flight SQL CommandGetTables with include_schema=true).
    /// </summary>
    internal static class FlightSqlSchemaHelper
    {
        /// <summary>
        /// Deserializes an Arrow <see cref="Schema"/> from IPC message bytes.
        /// </summary>
        public static Schema DeserializeSchema(byte[] schemaBytes)
        {
            using var stream = new MemoryStream(schemaBytes);
            using var reader = new ArrowStreamReader(stream);
            return reader.Schema;
        }
    }
}
