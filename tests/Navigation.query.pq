// Test navigation table: verify the connector returns test_data as a visible table.
// The Source parameter (from parameterquery.pq) is unused — this test directly
// calls GizmoSQL.Contents to verify the navigation table structure.
(Source) =>
let
    Nav = GizmoSQL.Contents("localhost", 31337, false, false)
in
    Nav
