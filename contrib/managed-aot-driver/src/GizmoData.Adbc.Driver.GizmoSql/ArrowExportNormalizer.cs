// Licensed under the Apache License, Version 2.0

using Apache.Arrow;

namespace GizmoData.Adbc.Driver.GizmoSql
{
    /// <summary>
    /// Rebuilds Arrow record batches so every buffer is backed by native memory.
    ///
    /// The Apache.Arrow.Flight client decodes record batches into buffers that
    /// are backed by managed <c>ReadOnlyMemory&lt;byte&gt;</c> (slices over the IPC
    /// message body). Apache.Arrow's C Data Interface exporter cannot export
    /// such buffers and throws
    /// "An ArrowArray of type ... could not be exported: failed on buffer #N".
    /// Power BI (and any other ADBC C-API consumer) reads results through that
    /// export path, so every batch is normalized to native buffers first.
    /// </summary>
    internal static class ArrowExportNormalizer
    {
        public static RecordBatch Normalize(RecordBatch batch)
        {
            var arrays = new IArrowArray[batch.ColumnCount];
            for (int i = 0; i < arrays.Length; i++)
            {
                arrays[i] = ArrowArrayFactory.BuildArray(Normalize(batch.Column(i).Data));
            }

            return new RecordBatch(batch.Schema, arrays, batch.Length);
        }

        private static ArrayData Normalize(ArrayData data)
        {
            var buffers = new ArrowBuffer[data.Buffers.Length];
            for (int i = 0; i < buffers.Length; i++)
            {
                buffers[i] = ToNative(data.Buffers[i]);
            }

            ArrayData[]? children = null;
            if (data.Children != null)
            {
                children = new ArrayData[data.Children.Length];
                for (int i = 0; i < children.Length; i++)
                {
                    children[i] = Normalize(data.Children[i]);
                }
            }

            ArrayData? dictionary = data.Dictionary != null ? Normalize(data.Dictionary) : null;

            return new ArrayData(data.DataType, data.Length, data.NullCount, data.Offset, buffers, children, dictionary);
        }

        private static ArrowBuffer ToNative(ArrowBuffer source)
        {
            if (source.Length == 0)
            {
                return ArrowBuffer.Empty;
            }

            // ArrowBuffer.Builder allocates from the native memory allocator, so
            // the resulting buffer is pointer-pinnable and export-safe.
            var builder = new ArrowBuffer.Builder<byte>(source.Length);
            builder.Append(source.Span);
            return builder.Build();
        }
    }
}
