let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    Table = Source{[Name="""memory"".""main"".""test_data""", Kind="Table"]}[Data]
in
    Table
