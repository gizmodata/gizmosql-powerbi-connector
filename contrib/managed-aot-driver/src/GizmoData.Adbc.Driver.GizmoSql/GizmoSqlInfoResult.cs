// Licensed under the Apache License, Version 2.0

using System;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Apache.Arrow;
using Apache.Arrow.Adbc;
using Apache.Arrow.Ipc;
using Apache.Arrow.Types;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Returns driver/database metadata via the ADBC GetInfo interface.
    /// Conforms to <see cref="StandardSchemas.GetInfoSchema"/>.
    /// </summary>
    internal class GizmoSqlInfoResult : IArrowArrayStream
    {
        private readonly IReadOnlyList<AdbcInfoCode> _codes;
        private bool _consumed;

        private static readonly string DriverVersion =
            typeof(GizmoSqlInfoResult).Assembly.GetName().Version?.ToString() ?? "0.1.0";

        public GizmoSqlInfoResult(IReadOnlyList<AdbcInfoCode> codes)
        {
            _codes = codes;
        }

        public Schema Schema => StandardSchemas.GetInfoSchema;

        public ValueTask<RecordBatch?> ReadNextRecordBatchAsync(CancellationToken cancellationToken = default)
        {
            if (_consumed)
                return new ValueTask<RecordBatch?>((RecordBatch?)null);

            _consumed = true;

            var infoNames = new UInt32Array.Builder();

            // For the union value column, we build a dense union.
            // For simplicity, all our info values are strings (type index 0).
            var typeIds = new List<byte>();
            var offsets = new List<int>();
            var stringValues = new StringArray.Builder();
            var boolValues = new BooleanArray.Builder();
            var int64Values = new Int64Array.Builder();
            var int32Values = new Int32Array.Builder();

            // Empty arrays for unused union children
            var stringListOffsets = new ArrowBuffer.Builder<int>();
            stringListOffsets.Append(0);
            var mapListOffsets = new ArrowBuffer.Builder<int>();
            mapListOffsets.Append(0);

            int stringCount = 0;
            int boolCount = 0;
            int int64Count = 0;

            foreach (var code in _codes)
            {
                switch (code)
                {
                    case AdbcInfoCode.VendorName:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append("GizmoSQL");
                        break;

                    case AdbcInfoCode.VendorVersion:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append("1.0");
                        break;

                    case AdbcInfoCode.VendorArrowVersion:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append("22.1.0");
                        break;

                    case AdbcInfoCode.DriverName:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append("GizmoData.Adbc.Driver.GizmoSql");
                        break;

                    case AdbcInfoCode.DriverVersion:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append(DriverVersion);
                        break;

                    case AdbcInfoCode.DriverArrowVersion:
                        infoNames.Append((uint)code);
                        typeIds.Add(0);
                        offsets.Add(stringCount++);
                        stringValues.Append("22.1.0");
                        break;

                    case AdbcInfoCode.VendorSql:
                        infoNames.Append((uint)code);
                        typeIds.Add(1);
                        offsets.Add(boolCount++);
                        boolValues.Append(true);
                        break;

                    case AdbcInfoCode.VendorSubstrait:
                        infoNames.Append((uint)code);
                        typeIds.Add(1);
                        offsets.Add(boolCount++);
                        boolValues.Append(false);
                        break;

                    case AdbcInfoCode.DriverAdbcVersion:
                        infoNames.Append((uint)code);
                        typeIds.Add(2);
                        offsets.Add(int64Count++);
                        int64Values.Append(1001000); // ADBC 1.1.0
                        break;
                }
            }

            var infoNamesArray = infoNames.Build();
            int length = infoNamesArray.Length;

            // Build the dense union array
            var typeIdsBuffer = new ArrowBuffer.Builder<byte>();
            foreach (var t in typeIds) typeIdsBuffer.Append(t);

            var offsetsBuffer = new ArrowBuffer.Builder<int>();
            foreach (var o in offsets) offsetsBuffer.Append(o);

            var stringArr = stringValues.Build();
            var boolArr = boolValues.Build();
            var int64Arr = int64Values.Build();
            var int32Arr = int32Values.Build();

            // Build empty string list and map list children
            var emptyStringList = new ListArray(
                new ListType(new Field("item", StringType.Default, true)),
                0,
                stringListOffsets.Build(),
                new StringArray.Builder().Build(),
                ArrowBuffer.Empty);

            var mapEntryFields = new Field[]
            {
                new Field("key", Int32Type.Default, false),
                new Field("value", Int32Type.Default, true),
            };
            var emptyMapStruct = new StructArray(
                new StructType(mapEntryFields),
                0,
                new IArrowArray[] { new Int32Array.Builder().Build(), new Int32Array.Builder().Build() },
                ArrowBuffer.Empty);

            var emptyMapList = new ListArray(
                new ListType(new Field("entries", new StructType(mapEntryFields), false)),
                0,
                mapListOffsets.Build(),
                emptyMapStruct,
                ArrowBuffer.Empty);

            var unionType = (UnionType)StandardSchemas.GetInfoSchema.FieldsList[1].DataType;

            var unionArray = new DenseUnionArray(
                unionType,
                length,
                new IArrowArray[] { stringArr, boolArr, int64Arr, int32Arr, emptyStringList, emptyMapList },
                typeIdsBuffer.Build(),
                offsetsBuffer.Build());

            var batch = new RecordBatch(
                StandardSchemas.GetInfoSchema,
                new IArrowArray[] { infoNamesArray, unionArray },
                length);

            return new ValueTask<RecordBatch?>(batch);
        }

        public void Dispose()
        {
        }
    }
}
