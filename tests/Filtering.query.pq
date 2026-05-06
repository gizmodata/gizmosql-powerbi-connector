// Test filtering: verify that row filtering works (query folding pushes
// the WHERE clause to the server).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    Filtered = Table.SelectRows(TestData, each [id] = 1)
in
    Filtered
