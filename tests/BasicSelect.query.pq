(Source) =>
let
    Sorted = Table.Sort(Source, {{"id", Order.Ascending}}),
    FirstRow = Table.First(Sorted)
in
    FirstRow
