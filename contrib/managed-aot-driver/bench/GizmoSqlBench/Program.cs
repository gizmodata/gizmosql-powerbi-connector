// Licensed under the Apache License, Version 2.0
//
// Throughput benchmark for the GizmoSQL ADBC driver. Measures how fast the
// driver pulls Arrow data from a GizmoSQL server (the work the Power BI
// connector does under the hood), and isolates the cost of the export-buffer
// normalization copy added in GizmoSqlResult.
//
// Configure via environment variables (same as the integration tests):
//   GIZMOSQL_TEST_HOST=grpc+tls://localhost:31337   (required)
//   GIZMOSQL_TEST_USERNAME=admin
//   GIZMOSQL_TEST_PASSWORD=...
//   GIZMOSQL_TEST_TLS_SKIP_VERIFY=true
//   GIZMOSQL_BENCH_QUERY="SELECT * FROM my_table"        (or pass as arg[0])
//   GIZMOSQL_BENCH_RUNS=3                                 (default 1)
//
// Run:  dotnet run -c Release --project bench/GizmoSqlBench -- "SELECT * FROM my_table"

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Apache.Arrow;
using GizmoData.Adbc.Driver.GizmoSql;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        string? host = Environment.GetEnvironmentVariable("GIZMOSQL_TEST_HOST");
        if (string.IsNullOrEmpty(host))
        {
            Console.Error.WriteLine("Set GIZMOSQL_TEST_HOST (e.g. grpc+tls://localhost:31337).");
            return 2;
        }

        string query = args.Length > 0
            ? args[0]
            : Environment.GetEnvironmentVariable("GIZMOSQL_BENCH_QUERY") ?? "SELECT 1";
        int runs = int.TryParse(Environment.GetEnvironmentVariable("GIZMOSQL_BENCH_RUNS"), out int r) && r > 0 ? r : 1;

        var parameters = new Dictionary<string, string>
        {
            [GizmoSqlParameters.ServerAddress] = host,
        };
        Add(parameters, GizmoSqlParameters.Username, "GIZMOSQL_TEST_USERNAME");
        Add(parameters, GizmoSqlParameters.Password, "GIZMOSQL_TEST_PASSWORD");
        if (string.Equals(Environment.GetEnvironmentVariable("GIZMOSQL_TEST_TLS_SKIP_VERIFY"), "true", StringComparison.OrdinalIgnoreCase))
            parameters[GizmoSqlParameters.TlsSkipVerify] = "true";

        Console.WriteLine($"Server : {host}");
        Console.WriteLine($"Query  : {query}");
        Console.WriteLine($"Runs   : {runs}");
        Console.WriteLine(new string('-', 60));

        var driver = new GizmoSqlDriver();
        using var database = driver.Open(parameters);
        using var connection = database.Connect(null);

        for (int run = 1; run <= runs; run++)
        {
            GizmoSqlResult.ResetStats();

            long rows = 0, bytes = 0, batches = 0;
            double firstBatchMs = -1;

            using var statement = connection.CreateStatement();
            statement.SqlQuery = query;

            var sw = Stopwatch.StartNew();
            var result = statement.ExecuteQuery();

            while (true)
            {
                var batch = await result.Stream!.ReadNextRecordBatchAsync();
                if (batch == null) break;
                if (firstBatchMs < 0) firstBatchMs = sw.Elapsed.TotalMilliseconds;

                rows += batch.Length;
                batches++;
                for (int c = 0; c < batch.ColumnCount; c++)
                    bytes += ByteSize(batch.Column(c).Data);
                batch.Dispose();
            }
            sw.Stop();

            double sec = sw.Elapsed.TotalSeconds;
            double mb = bytes / (1024.0 * 1024.0);
            double normSec = (double)GizmoSqlResult.NormalizeTicks / Stopwatch.Frequency;

            Console.WriteLine($"Run {run}:");
            Console.WriteLine($"  rows           : {rows:N0}");
            Console.WriteLine($"  data           : {mb:N1} MB ({bytes:N0} bytes, Arrow buffer size)");
            Console.WriteLine($"  batches        : {batches:N0} (avg {(batches > 0 ? rows / batches : 0):N0} rows/batch)");
            Console.WriteLine($"  total time     : {sec * 1000:N0} ms");
            Console.WriteLine($"  time to 1st    : {firstBatchMs:N0} ms (server query + first transfer)");
            Console.WriteLine($"  throughput     : {(sec > 0 ? rows / sec : 0):N0} rows/s | {(sec > 0 ? mb / sec : 0):N1} MB/s");
            Console.WriteLine($"  normalize copy : {normSec * 1000:N0} ms ({(sec > 0 ? 100.0 * normSec / sec : 0):N1}% of total)");
            Console.WriteLine(new string('-', 60));
        }

        return 0;
    }

    private static void Add(Dictionary<string, string> p, string key, string envVar)
    {
        string? v = Environment.GetEnvironmentVariable(envVar);
        if (!string.IsNullOrEmpty(v)) p[key] = v;
    }

    // Sum of all buffer bytes in an array (recursing into children + dictionary).
    private static long ByteSize(ArrayData data)
    {
        long total = 0;
        foreach (var buf in data.Buffers)
            total += buf.Length;
        if (data.Children != null)
            foreach (var child in data.Children)
                total += ByteSize(child);
        if (data.Dictionary != null)
            total += ByteSize(data.Dictionary);
        return total;
    }
}
