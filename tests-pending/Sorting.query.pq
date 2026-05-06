// Test sorting: verify ORDER BY folding works correctly.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    Sorted = Table.Sort(TestData, {{"value", Order.Descending}})
in
    Sorted
