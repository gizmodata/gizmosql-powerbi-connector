// Test data types: verify the connector correctly returns all column types
// from the test_data table (INTEGER, VARCHAR, DOUBLE).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    TestData = Source{[Name="test_data", Schema="main", Catalog="memory"]}[Data],
    FirstRow = Table.First(TestData)
in
    TestData
