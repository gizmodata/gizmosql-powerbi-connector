// Test LIMIT: verify that Table.FirstN folds to LIMIT clause.
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Item="test_data", Schema="main", Catalog="memory"]}[Data],
    Top2 = Table.FirstN(TestData, 2)
in
    Top2
