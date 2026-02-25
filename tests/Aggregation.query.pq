// Test aggregation: verify GROUP BY and SUM folding works correctly.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Item="test_data", Schema="main", Catalog="memory"]}[Data],
    Grouped = Table.Group(TestData, {"name"}, {{"Total", each List.Sum([value]), type number}})
in
    Grouped
