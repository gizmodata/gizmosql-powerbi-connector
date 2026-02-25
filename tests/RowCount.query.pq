// Test row count: verify the connector returns the expected number of rows.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Item="test_data", Schema="main", Catalog="memory"]}[Data],
    RowCount = Table.RowCount(TestData)
in
    RowCount
