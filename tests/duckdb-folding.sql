-- Sanity-check the SQL idioms emitted by SqlGenerator.pqm against DuckDB.
-- Run with: duckdb < tests/duckdb-folding.sql
-- Each query should return the expected value in the comment, with no errors.

CREATE TEMP TABLE tcal AS SELECT
    DATE     '2024-06-15'             AS d,
    TIMESTAMP '2024-06-15 14:30:45.123' AS ts,
    TIME     '14:30:45.123456'         AS t;

-- DateStartOfHelper: date_trunc('unit', x)
SELECT 'StartOfYear'    fn, date_trunc('year',    d)::VARCHAR r FROM tcal      -- 2024-01-01
UNION ALL SELECT 'StartOfQuarter', date_trunc('quarter', d)::VARCHAR FROM tcal -- 2024-04-01
UNION ALL SELECT 'StartOfMonth',   date_trunc('month',   d)::VARCHAR FROM tcal -- 2024-06-01
UNION ALL SELECT 'StartOfWeek',    date_trunc('week',    d)::VARCHAR FROM tcal -- 2024-06-10
UNION ALL SELECT 'StartOfDay',     date_trunc('day',     ts)::VARCHAR FROM tcal -- 2024-06-15 00:00:00
-- DateEndOfHelper: date_trunc + to_<unit>(1) - to_<sub>(1)
UNION ALL SELECT 'EndOfYear_date',   (date_trunc('year',  d)  + to_years(1)  - to_days(1))::VARCHAR FROM tcal             -- 2024-12-31
UNION ALL SELECT 'EndOfMonth_ts',    (date_trunc('month', ts) + to_months(1) - to_microseconds(1))::VARCHAR FROM tcal     -- 2024-06-30 23:59:59.999999
-- DateAddHelper: x + to_<unit>(n)
UNION ALL SELECT 'AddYears(2)',     (d + to_years(2))::VARCHAR    FROM tcal     -- 2026-06-15
UNION ALL SELECT 'AddDays(7)',      (d + to_days(7))::VARCHAR     FROM tcal     -- 2024-06-22
UNION ALL SELECT 'AddMonths(-3)',   (d + to_months(-3))::VARCHAR  FROM tcal     -- 2024-03-15
-- IntFromHelper / Single.From / Double.From (date branch): date_diff('day', anchor, x)
UNION ALL SELECT 'DaysSinceAnchor', date_diff('day', DATE '1899-12-30', d)::VARCHAR FROM tcal -- 45458
-- ConvertToDoubleFromDateTime: (epoch_us(x) - epoch_us(anchor)) / 86400000000.0
UNION ALL SELECT 'TsAsOleDouble',   ((epoch_us(ts) - epoch_us(TIMESTAMP '1899-12-30')) / 86400000000.0)::VARCHAR FROM tcal -- ~45458.6046
-- Date.From (number branch): anchor + to_days(n)
UNION ALL SELECT 'NumberToDate',    (DATE '1899-12-30' + to_days(45458))::VARCHAR              -- 2024-06-15
-- DateTime.From (number branch): anchor + to_microseconds(n * 86400000000)
UNION ALL SELECT 'NumberToDateTime',(TIMESTAMP '1899-12-30' + to_microseconds(CAST(45458.5 * 86400000000 AS BIGINT)))::VARCHAR -- 2024-06-15 12:00:00
-- DateTime.From (time branch): anchor + to_microseconds(epoch_us(t))
UNION ALL SELECT 'TimeToDateTime', (TIMESTAMP '1899-12-30' + to_microseconds(CAST(epoch_us(t) AS BIGINT)))::VARCHAR FROM tcal -- 1899-12-30 14:30:45.123456
-- Time.StartOfHour / Time.EndOfHour: make_time(hour(t), 0|59, 0|59.999999)
UNION ALL SELECT 'StartOfHour_t',  make_time(hour(t), 0,  0.0)::VARCHAR  FROM tcal             -- 14:00:00
UNION ALL SELECT 'EndOfHour_t',    make_time(hour(t), 59, 59.999999)::VARCHAR FROM tcal       -- 14:59:59.999999
-- Time.Second: microsecond(t)::DOUBLE / 1e6
UNION ALL SELECT 'Second_t',  (microsecond(t)::DOUBLE  / 1000000.0)::VARCHAR FROM tcal         -- ~45.123456
UNION ALL SELECT 'Second_ts', (microsecond(ts)::DOUBLE / 1000000.0)::VARCHAR FROM tcal         -- ~45.123
-- Text.PositionOf: instr(haystack, needle) - 1
UNION ALL SELECT 'PosOf_found',     (instr('hello world', 'wor') - 1)::VARCHAR                 -- 6
UNION ALL SELECT 'PosOf_missing',   (instr('hello world', 'XXX') - 1)::VARCHAR                 -- -1
-- Text.RemoveRange: concat(substring(s, 1, offset), substring(s, offset + count + 1))
UNION ALL SELECT 'RemoveRange(2,3)', concat(substring('hello world', 1, 2), substring('hello world', 2 + 3 + 1)) -- he world
-- Logical.From (text branch): CAST(x AS VARCHAR) replaces TO_VARCHAR
UNION ALL SELECT 'AsVarchar',       CAST(42 AS VARCHAR);                                       -- 42
