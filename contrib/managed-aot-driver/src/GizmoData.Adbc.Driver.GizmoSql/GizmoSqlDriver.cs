// Licensed under the Apache License, Version 2.0

using System.Collections.Generic;
using Apache.Arrow.Adbc;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// ADBC driver entry point for GizmoSQL.
    /// </summary>
    public class GizmoSqlDriver : AdbcDriver
    {
        /// <summary>
        /// Opens a new <see cref="GizmoSqlDatabase"/> with the given parameters.
        /// </summary>
        public override AdbcDatabase Open(IReadOnlyDictionary<string, string>? parameters)
        {
            return new GizmoSqlDatabase(parameters);
        }
    }
}
