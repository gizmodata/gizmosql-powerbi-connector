// Test query for the Power Query SDK: connect, authenticate, and show the
// catalog navigation table.
let
    Nav = GizmoSQL.Contents("localhost", 31337, false, false)
in
    Nav
