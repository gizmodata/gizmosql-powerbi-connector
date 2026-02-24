// Test parameterized query: Table.SelectRows should fold into
// SELECT ... FROM "test_data" WHERE "id" = ? with a bound parameter.
// Expects exactly 1 row with id=1, name="alice", value=3.14.
(Source) =>
let
    Filtered = Table.SelectRows(Source, each [id] = 1),
    FirstRow = Table.First(Filtered)
in
    FirstRow
