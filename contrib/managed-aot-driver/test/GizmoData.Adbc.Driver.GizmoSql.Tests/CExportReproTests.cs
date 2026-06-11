// Licensed under the Apache License, Version 2.0

using System;
using Apache.Arrow;
using Apache.Arrow.C;
using Apache.Arrow.Types;
using Xunit;

namespace GizmoData.Adbc.Driver.GizmoSql.Tests
{
    /// <summary>
    /// Reproduces the Power BI failure "An ArrowArray of type String could not
    /// be exported: failed on buffer #1" in isolation, to determine whether the
    /// C Data Interface export of String arrays is broken in the resolved
    /// Apache.Arrow version (22.1.0) or only for Flight-sourced (sliced) arrays.
    /// </summary>
    public class CExportReproTests
    {
        private static unsafe void ExportRoundTrip(IArrowArray array)
        {
            CArrowArray* c = CArrowArray.Create();
            try
            {
                CArrowArrayExporter.ExportArray(array, c);
            }
            finally
            {
                CArrowArray.Free(c);
            }
        }

        private static StringArray BuildStrings(params string?[] values)
        {
            var b = new StringArray.Builder();
            foreach (var v in values)
            {
                if (v == null) b.AppendNull(); else b.Append(v);
            }
            return b.Build();
        }

        [Fact]
        public void Export_PlainStringArray()
        {
            ExportRoundTrip(BuildStrings("memory", "main", "info"));
        }

        [Fact]
        public void Export_StringArray_WithNulls()
        {
            ExportRoundTrip(BuildStrings("a", null, "ccc", null));
        }

        [Fact]
        public void Export_EmptyStringArray()
        {
            ExportRoundTrip(BuildStrings());
        }

        [Fact]
        public void Export_SlicedStringArray()
        {
            // Mimics a Flight-decoded array that is a view with a non-zero offset.
            var full = BuildStrings("zero", "one", "two", "three");
            var sliced = (StringArray)ArrowArrayFactory.Slice(full, 1, 2);
            ExportRoundTrip(sliced);
        }

        [Fact]
        public void Export_ReadOnlyMemoryBackedStringArray_ThrowsWithoutNormalization()
        {
            // Documents the root cause: a Flight-decoded StringArray has buffers
            // backed by managed ReadOnlyMemory (slices over the IPC body), NOT
            // native ArrowBuffers, and the C exporter cannot export those.
            // GizmoSqlResult fixes this by running batches through
            // ArrowExportNormalizer (see Normalize_MakesReadOnlyMemoryStringExportable).
            var ex = Assert.Throws<NotSupportedException>(() => ExportRoundTrip(BuildReadOnlyMemoryStrings()));
            Assert.Contains("failed on buffer", ex.Message);
        }

        private static StringArray BuildReadOnlyMemoryStrings()
        {
            byte[] values = System.Text.Encoding.UTF8.GetBytes("abcde");
            byte[] offsets = new byte[3 * sizeof(int)];
            BitConverter.GetBytes(0).CopyTo(offsets, 0);
            BitConverter.GetBytes(2).CopyTo(offsets, 4);
            BitConverter.GetBytes(5).CopyTo(offsets, 8);
            var data = new ArrayData(
                StringType.Default, length: 2, nullCount: 0, offset: 0,
                buffers: new[]
                {
                    ArrowBuffer.Empty,
                    new ArrowBuffer(new ReadOnlyMemory<byte>(offsets)),
                    new ArrowBuffer(new ReadOnlyMemory<byte>(values)),
                });
            return new StringArray(data);
        }

        [Fact]
        public void Normalize_MakesReadOnlyMemoryStringExportable()
        {
            var arr = BuildReadOnlyMemoryStrings();
            var schema = new Schema(new[] { new Field("name", StringType.Default, true) }, null);
            var batch = new RecordBatch(schema, new IArrowArray[] { arr }, arr.Length);

            var normalized = ArrowExportNormalizer.Normalize(batch);

            // Data must survive the round-trip...
            var col = (StringArray)normalized.Column(0);
            Assert.Equal("ab", col.GetString(0));
            Assert.Equal("cde", col.GetString(1));

            // ...and now export through the C Data Interface without throwing.
            unsafe
            {
                CArrowArray* c = CArrowArray.Create();
                try { CArrowArrayExporter.ExportRecordBatch(normalized, c); }
                finally { CArrowArray.Free(c); }
            }
        }

        [Fact]
        public void Export_RecordBatch_WithStringColumn()
        {
            var arr = BuildStrings("catalog1", "catalog2");
            var schema = new Schema(new[] { new Field("name", StringType.Default, true) }, null);
            var batch = new RecordBatch(schema, new IArrowArray[] { arr }, arr.Length);
            unsafe
            {
                CArrowArray* c = CArrowArray.Create();
                try { CArrowArrayExporter.ExportRecordBatch(batch, c); }
                finally { CArrowArray.Free(c); }
            }
        }
    }
}
