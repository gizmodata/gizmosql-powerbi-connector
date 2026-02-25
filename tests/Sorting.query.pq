// Test sorting: verify ORDER BY folding works correctly.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="test_data", Schema="main", Catalog="memory"]}[Data],
    Sorted = Table.Sort(TestData, {{"value", Order.Descending}})
in
    Sorted
