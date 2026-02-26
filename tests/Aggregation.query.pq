// Test aggregation: verify GROUP BY and SUM folding works correctly.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    Grouped = Table.Group(TestData, {"name"}, {{"Total", each List.Sum([value]), type number}})
in
    Grouped
