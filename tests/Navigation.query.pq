// Test navigation table: verify the connector can connect, authenticate,
// and enumerate tables from the GizmoSQL server.
let
    Nav = GizmoSQL.Contents("localhost", 31337, false, false)
in
    Nav
