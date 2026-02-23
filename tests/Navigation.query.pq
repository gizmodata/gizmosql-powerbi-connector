let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    ColumnNames = Table.ColumnNames(Source),
    RowCount = Table.RowCount(Source),
    ColumnInfo = Text.Combine(ColumnNames, ", "),
    Result = Record.FromList({RowCount, ColumnInfo, Value.Type(Source)}, {"RowCount", "Columns", "SourceType"})
in
    Result
