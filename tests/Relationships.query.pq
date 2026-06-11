// Test the primary-key / foreign-key schema that backs relationship detection.
//
// Fixture (CI init-sql): dept(dept_id PK, dname) and
// emp(emp_id PK, dept_id REFERENCES dept(dept_id), ename).
//
// SCOPE / LIMITATION: automatic foreign-key relationship detection is a Power BI
// Desktop *model-layer* behavior. PQTest evaluates M and inspects table values;
// it cannot observe model-view relationships, so the emp->dept relationship
// itself must be verified manually in Power BI Desktop's Model view. This test
// guards the layer beneath that: both tables navigate, carry the expected data,
// and declare their primary keys. Extend the marked section once the connector
// emits foreign-key metadata (see GizmoSQL.pq GetTableType / GetPrimaryKeys).
let
    Source = GizmoSQL.Contents("localhost", 31337, false, false),
    Database = Source{[Name = "memory"]}[Data],
    Schema = Database{[Name = "main"]}[Data],

    Dept = Schema{[Name = "dept"]}[Data],
    Emp = Schema{[Name = "emp"]}[Data],

    Assert = (label as text, condition as logical) as logical =>
        if condition then true else error Error.Record("Test.Assert", "FAILED: " & label),

    // --- Navigation + data round-trips over a PK/FK schema ---
    checkDeptRows = Assert("dept has 2 rows", Table.RowCount(Dept) = 2),
    checkEmpRows = Assert("emp has 2 rows", Table.RowCount(Emp) = 2),
    checkEmpCols = Assert(
        "emp exposes emp_id, dept_id, ename",
        List.ContainsAll(Table.ColumnNames(Emp), {"emp_id", "dept_id", "ename"})
    ),

    // --- Primary keys are declared (the 'one' side a relationship needs) ---
    deptKeys = Table.Keys(Dept),
    empKeys = Table.Keys(Emp),
    checkDeptPk = Assert(
        "dept declares primary key on dept_id",
        List.AnyTrue(List.Transform(deptKeys, each [Primary] = true and [Columns] = {"dept_id"}))
    ),
    checkEmpPk = Assert(
        "emp declares primary key on emp_id",
        List.AnyTrue(List.Transform(empKeys, each [Primary] = true and [Columns] = {"emp_id"}))
    ),

    // --- TODO(relationships): once the connector emits the emp.dept_id ->
    // dept.dept_id foreign key (e.g. via Table.NestedJoin nav properties),
    // assert the relationship metadata here. PQTest still can't confirm it lands
    // in the model, but it can confirm the connector emits it. ---

    allChecks = {checkDeptRows, checkEmpRows, checkEmpCols, checkDeptPk, checkEmpPk},
    Result = Table.FromRecords({[
        Test = "Relationships",
        DeptRows = Table.RowCount(Dept),
        EmpRows = Table.RowCount(Emp),
        ChecksPassed = List.Count(List.Select(allChecks, each _ = true))
    ]})
in
    Result
