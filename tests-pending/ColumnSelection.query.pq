// Test column selection: verify that selecting a subset of columns works
// (query folding pushes column pruning to the server).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    SelectedColumns = Table.SelectColumns(TestData, {"id", "name"})
in
    SelectedColumns
