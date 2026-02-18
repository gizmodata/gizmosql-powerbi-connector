let
    source = GizmoSQL.Contents("localhost", 31337),
    firstDb = source{0}[Data],
    firstSchema = firstDb{0}[Data],
    firstTable = firstSchema{0}[Data]
in
    Table.FirstN(firstTable, 5)
