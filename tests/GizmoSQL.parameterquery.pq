let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    Database = Source{[Name="memory", Kind="Database"]}[Data],
    Schema = Database{[Name="main", Kind="Schema"]}[Data],
    Table = Schema{[Name="test_data", Kind="Table"]}[Data]
in
    Table
