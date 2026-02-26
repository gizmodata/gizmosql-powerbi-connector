// Test data types: verify the connector correctly returns all column types
// from the test_data table (INTEGER, VARCHAR, DOUBLE).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    FirstRow = Table.First(TestData)
in
    TestData
