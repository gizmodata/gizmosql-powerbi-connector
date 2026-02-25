// Test filtering: verify that row filtering works (query folding pushes
// the WHERE clause to the server).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="test_data", Schema="main", Catalog="memory"]}[Data],
    Filtered = Table.SelectRows(TestData, each [id] = 1)
in
    Filtered
