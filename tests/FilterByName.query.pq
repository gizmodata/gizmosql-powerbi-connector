// Test parameterized query with string value: Table.SelectRows should fold
// into SELECT ... FROM "test_data" WHERE "name" = ? with a bound string parameter.
// Expects exactly 1 row with id=2, name="bob", value=2.72.
(Source) =>
let
    Filtered = Table.SelectRows(Source, each [name] = "bob"),
    FirstRow = Table.First(Filtered)
in
    FirstRow
