// Test LIMIT: verify that Table.FirstN folds to LIMIT clause.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    Top2 = Table.FirstN(TestData, 2)
in
    Top2
