// Licensed under the Apache License, Version 2.0

using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using Apache.Arrow.Adbc;
using Apache.Arrow.Adbc.C;

namespace GizmoData.Adbc.Driver.GizmoSql.Native
{
    // The C ABI entrypoint for the AOT-compiled native DLL. The ADBC driver
    // manager (and Power BI's "Unmanaged" ADBC driver loader, and Python's
    // adbc_driver_manager) resolves this exported symbol, then calls it once at
    // load time to populate the function-pointer table in *driver*.
    //
    // Wire shape (ADBC 1.1.0):
    //   AdbcStatusCode GizmoSqlAdbcDriverInit(
    //       int version,
    //       CAdbcDriver* driver,
    //       CAdbcError* error);
    //
    // All the heavy lifting (mapping the managed GizmoSqlDriver methods onto the
    // C struct of function pointers) lives inside Apache.Arrow.Adbc's
    // CAdbcDriverExporter. We just hand it a fresh GizmoSqlDriver and forward.
    internal static class Entrypoint
    {
        // ADBC version constants follow MAJOR*1_000_000 + MINOR*1_000 + PATCH.
        private const int AdbcVersion_1_0_0 = 1_000_000;
        private const int AdbcVersion_1_1_0 = 1_001_000;

        [UnmanagedCallersOnly(EntryPoint = "GizmoSqlAdbcDriverInit", CallConvs = new[] { typeof(CallConvCdecl) })]
        public static unsafe AdbcStatusCode GizmoSqlAdbcDriverInit(int version, CAdbcDriver* driver, CAdbcError* error)
        {
            try
            {
                // The CAdbcDriverExporter populates the ADBC 1.0.0 entry points.
                // Driver managers may advertise 1.1.0; the CAdbcDriver struct is a
                // superset, so we forward as 1.0.0 and leave 1.1.0-only function
                // pointers null (the manager treats null as "not supported").
                if (version != AdbcVersion_1_0_0 && version != AdbcVersion_1_1_0)
                {
                    return AdbcStatusCode.NotImplemented;
                }

                return CAdbcDriverExporter.AdbcDriverInit(
                    AdbcVersion_1_0_0, driver, error, new GizmoSqlDriver());
            }
            catch
            {
                return AdbcStatusCode.UnknownError;
            }
        }
    }
}
