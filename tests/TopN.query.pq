// Test parameterized LIMIT: Table.FirstN should fold into
// SELECT ... FROM "test_data" LIMIT ? with a bound integer parameter.
// This is the exact pattern Power BI DirectQuery generates.
// Expects 2 rows returned.
(Source) =>
let
    TopTwo = Table.FirstN(Source, 2)
in
    TopTwo
