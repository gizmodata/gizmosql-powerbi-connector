// Test row count: verify the connector returns the expected number of rows.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    RowCount = Table.RowCount(TestData)
in
    RowCount
