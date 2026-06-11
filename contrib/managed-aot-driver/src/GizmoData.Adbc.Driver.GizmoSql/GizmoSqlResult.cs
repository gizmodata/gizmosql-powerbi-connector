// Licensed under the Apache License, Version 2.0

using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Apache.Arrow;
using Apache.Arrow.Flight;
using Apache.Arrow.Flight.Client;
using Apache.Arrow.Ipc;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Streams <see cref="RecordBatch"/> results from Flight endpoints.
    /// Handles multi-endpoint results (distributed data).
    /// Unlike the upstream FlightSqlResult, this does NOT dispose the connection
    /// when the result stream is disposed.
    /// </summary>
    internal class GizmoSqlResult : IArrowArrayStream
    {
        private readonly GizmoSqlConnection _connection;
        private readonly FlightInfo _flightInfo;
        private readonly int _maxEndpoints;

        private FlightClientRecordBatchStreamReader? _currentReader;
        private int _currentEndpointIndex = -1;

        public GizmoSqlResult(GizmoSqlConnection connection, FlightInfo flightInfo)
        {
            _connection = connection;
            _flightInfo = flightInfo;
            _maxEndpoints = flightInfo.Endpoints.Count;
        }

        public Schema Schema => _flightInfo.Schema;

        // Diagnostic counters (used by the benchmark harness) measuring how much
        // time the export normalization copy adds. Not thread-safe by design —
        // intended for single-stream benchmarking only.
        internal static long NormalizeTicks;
        internal static long NormalizeBatches;

        internal static void ResetStats()
        {
            NormalizeTicks = 0;
            NormalizeBatches = 0;
        }

        private static RecordBatch NormalizeTimed(RecordBatch batch)
        {
            long start = Stopwatch.GetTimestamp();
            var normalized = ArrowExportNormalizer.Normalize(batch);
            NormalizeTicks += Stopwatch.GetTimestamp() - start;
            NormalizeBatches++;
            return normalized;
        }

        public async ValueTask<RecordBatch?> ReadNextRecordBatchAsync(CancellationToken cancellationToken = default)
        {
            if (_currentReader == null)
            {
                if (!MoveToNextEndpoint())
                    return null;
            }

            if (await _currentReader!.MoveNext(cancellationToken))
            {
                return NormalizeTimed(_currentReader.Current);
            }

            // Current endpoint exhausted, try the next one
            _currentReader?.Dispose();
            _currentReader = null;

            if (!MoveToNextEndpoint())
                return null;

            if (await _currentReader!.MoveNext(cancellationToken))
            {
                return NormalizeTimed(_currentReader.Current);
            }

            return null;
        }

        private bool MoveToNextEndpoint()
        {
            _currentEndpointIndex++;
            if (_currentEndpointIndex >= _maxEndpoints)
                return false;

            var endpoint = _flightInfo.Endpoints[_currentEndpointIndex];
            _currentReader = _connection.FlightClient
                .GetStream(endpoint.Ticket, _connection.AuthHeaders)
                .ResponseStream;

            return true;
        }

        public void Dispose()
        {
            _currentReader?.Dispose();
            _currentReader = null;
            // Intentionally do NOT dispose the connection
        }
    }
}
