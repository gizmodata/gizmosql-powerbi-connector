// Licensed under the Apache License, Version 2.0

using System;
using System.Collections.Generic;
using Apache.Arrow.Adbc;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Represents a GizmoSQL database instance. Holds connection parameters
    /// and creates <see cref="GizmoSqlConnection"/> instances.
    /// </summary>
    public class GizmoSqlDatabase : AdbcDatabase
    {
        private readonly IReadOnlyDictionary<string, string>? _parameters;

        public GizmoSqlDatabase(IReadOnlyDictionary<string, string>? parameters)
        {
            _parameters = parameters;
        }

        /// <summary>
        /// Creates and opens a new connection to the GizmoSQL server.
        /// </summary>
        /// <param name="options">Additional connection options (merged with database parameters).</param>
        public override AdbcConnection Connect(IReadOnlyDictionary<string, string>? options)
        {
            // Merge database-level params with connection-level options
            var merged = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            if (_parameters != null)
            {
                foreach (var kvp in _parameters)
                {
                    merged[kvp.Key] = kvp.Value;
                }
            }

            if (options != null)
            {
                foreach (var kvp in options)
                {
                    merged[kvp.Key] = kvp.Value;
                }
            }

            var connection = new GizmoSqlConnection(merged);
            connection.Open();
            return connection;
        }
    }
}
