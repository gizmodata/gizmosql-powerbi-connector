#include <windows.h>
#include <sql.h>
#include <sqlext.h>
#include <stdio.h>

void check_error(SQLRETURN ret, SQLSMALLINT handleType, SQLHANDLE handle, const char *msg) {
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
        SQLCHAR sqlState[6], errorMsg[512];
        SQLINTEGER nativeError;
        SQLSMALLINT msgLen;
        SQLGetDiagRecA(handleType, handle, 1, sqlState, &nativeError, errorMsg, sizeof(errorMsg), &msgLen);
        fprintf(stderr, "%s: ret=%d, state=%s, error=%s\n", msg, ret, sqlState, errorMsg);
    }
}

void test_sqltables(SQLHSTMT hStmt, const char *label,
                    SQLCHAR *catalog, SQLSMALLINT catalogLen,
                    SQLCHAR *schema, SQLSMALLINT schemaLen,
                    SQLCHAR *table, SQLSMALLINT tableLen,
                    SQLCHAR *type, SQLSMALLINT typeLen) {
    printf("\n=== %s ===\n", label);
    printf("  catalog=%s, schema=%s, table=%s, type=%s\n",
           catalog ? (char*)catalog : "NULL",
           schema ? (char*)schema : "NULL",
           table ? (char*)table : "NULL",
           type ? (char*)type : "NULL");

    SQLRETURN ret = SQLTablesA(hStmt, catalog, catalogLen, schema, schemaLen,
                               table, tableLen, type, typeLen);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLTables");
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) return;

    SQLSMALLINT numCols;
    SQLNumResultCols(hStmt, &numCols);
    printf("  Columns: %d\n", numCols);

    printf("  ");
    for (int i = 1; i <= numCols; i++) {
        SQLCHAR colName[256];
        SQLSMALLINT colNameLen;
        SQLDescribeColA(hStmt, i, colName, sizeof(colName), &colNameLen, NULL, NULL, NULL, NULL);
        printf("%-20s", colName);
    }
    printf("\n");

    int rowCount = 0;
    while (1) {
        ret = SQLFetch(hStmt);
        if (ret == SQL_NO_DATA) break;
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLFetch");
            break;
        }
        rowCount++;
        printf("  ");
        for (int i = 1; i <= numCols; i++) {
            SQLCHAR val[256];
            SQLLEN indicator;
            SQLGetData(hStmt, i, SQL_C_CHAR, val, sizeof(val), &indicator);
            printf("%-20s", indicator == SQL_NULL_DATA ? "NULL" : (char*)val);
        }
        printf("\n");
    }
    printf("  Total rows: %d\n", rowCount);
    SQLCloseCursor(hStmt);
}

void test_sqltables_w(SQLHSTMT hStmt, const char *label,
                      SQLWCHAR *catalog, SQLSMALLINT catalogLen,
                      SQLWCHAR *schema, SQLSMALLINT schemaLen,
                      SQLWCHAR *table, SQLSMALLINT tableLen,
                      SQLWCHAR *type, SQLSMALLINT typeLen) {
    printf("\n=== %s ===\n", label);
    printf("  (Wide char version)\n");

    SQLRETURN ret = SQLTablesW(hStmt, catalog, catalogLen, schema, schemaLen,
                               table, tableLen, type, typeLen);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLTablesW");
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) return;

    SQLSMALLINT numCols;
    SQLNumResultCols(hStmt, &numCols);
    printf("  Columns: %d\n", numCols);

    int rowCount = 0;
    while (1) {
        ret = SQLFetch(hStmt);
        if (ret == SQL_NO_DATA) break;
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLFetch");
            break;
        }
        rowCount++;
        printf("  ");
        for (int i = 1; i <= numCols; i++) {
            SQLCHAR val[256];
            SQLLEN indicator;
            SQLGetData(hStmt, i, SQL_C_CHAR, val, sizeof(val), &indicator);
            printf("%-20s", indicator == SQL_NULL_DATA ? "NULL" : (char*)val);
        }
        printf("\n");
    }
    printf("  Total rows: %d\n", rowCount);
    SQLCloseCursor(hStmt);
}

int main() {
    SQLHENV hEnv;
    SQLHDBC hDbc;
    SQLHSTMT hStmt;
    SQLRETURN ret;

    SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &hEnv);
    SQLSetEnvAttr(hEnv, SQL_ATTR_ODBC_VERSION, (void*)SQL_OV_ODBC3, 0);
    SQLAllocHandle(SQL_HANDLE_DBC, hEnv, &hDbc);

    SQLCHAR connStr[] = "Driver={GizmoSQL ODBC Driver};host=localhost;port=31337;"
                        "useEncryption=false;UID=gizmosql_user;PWD=gizmosql_password;authType=basic";
    SQLCHAR connOut[1024];
    SQLSMALLINT connOutLen;

    printf("Connecting to GizmoSQL...\n");
    ret = SQLDriverConnectA(hDbc, NULL, connStr, SQL_NTS, connOut, sizeof(connOut),
                            &connOutLen, SQL_DRIVER_NOPROMPT);
    check_error(ret, SQL_HANDLE_DBC, hDbc, "SQLDriverConnect");
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
        fprintf(stderr, "Connection failed!\n");
        return 1;
    }
    printf("Connected!\n");

    SQLAllocHandle(SQL_HANDLE_STMT, hDbc, &hStmt);

    /* ANSI tests */
    test_sqltables(hStmt, "ANSI: All NULL params",
                   NULL, 0, NULL, 0, NULL, 0, NULL, 0);

    test_sqltables(hStmt, "ANSI: SQL_ALL_CATALOGS",
                   (SQLCHAR*)"%", SQL_NTS, (SQLCHAR*)"", SQL_NTS,
                   (SQLCHAR*)"", SQL_NTS, NULL, 0);

    test_sqltables(hStmt, "ANSI: Empty strings (not NULL)",
                   (SQLCHAR*)"", SQL_NTS, (SQLCHAR*)"", SQL_NTS,
                   (SQLCHAR*)"", SQL_NTS, (SQLCHAR*)"", SQL_NTS);

    /* Wide char tests - these match what Power Query uses */
    test_sqltables_w(hStmt, "WIDE: All NULL params",
                     NULL, 0, NULL, 0, NULL, 0, NULL, 0);

    test_sqltables_w(hStmt, "WIDE: SQL_ALL_CATALOGS",
                     L"%", SQL_NTS, L"", SQL_NTS, L"", SQL_NTS, NULL, 0);

    test_sqltables_w(hStmt, "WIDE: Empty strings (not NULL)",
                     L"", SQL_NTS, L"", SQL_NTS, L"", SQL_NTS, L"", SQL_NTS);

    test_sqltables_w(hStmt, "WIDE: Wildcard % for table",
                     NULL, 0, NULL, 0, L"%", SQL_NTS, NULL, 0);

    /* Test SQLColumnsW - this is what Power Query calls to discover columns */
    printf("\n=== WIDE: SQLColumnsW for test_data ===\n");
    ret = SQLColumnsW(hStmt, NULL, 0, NULL, 0, L"test_data", SQL_NTS, NULL, 0);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLColumnsW(test_data)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLSMALLINT numCols;
        SQLNumResultCols(hStmt, &numCols);
        printf("  Result columns: %d\n", numCols);
        int colRowCount = 0;
        while (1) {
            ret = SQLFetch(hStmt);
            if (ret == SQL_NO_DATA) break;
            if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
                check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLFetch(SQLColumnsW)");
                break;
            }
            colRowCount++;
            SQLCHAR cat[128], sch[128], tbl[128], col[128], typeName[128];
            SQLSMALLINT dataType;
            SQLLEN ind_cat, ind_sch, ind_tbl, ind_col, ind_dt, ind_tn;
            SQLGetData(hStmt, 1, SQL_C_CHAR, cat, sizeof(cat), &ind_cat);
            SQLGetData(hStmt, 2, SQL_C_CHAR, sch, sizeof(sch), &ind_sch);
            SQLGetData(hStmt, 3, SQL_C_CHAR, tbl, sizeof(tbl), &ind_tbl);
            SQLGetData(hStmt, 4, SQL_C_CHAR, col, sizeof(col), &ind_col);
            SQLGetData(hStmt, 5, SQL_C_SSHORT, &dataType, 0, &ind_dt);
            SQLGetData(hStmt, 6, SQL_C_CHAR, typeName, sizeof(typeName), &ind_tn);
            printf("  cat=%s sch=%s tbl=%s col=%s type=%d(%s)\n",
                   ind_cat == SQL_NULL_DATA ? "NULL" : (char*)cat,
                   ind_sch == SQL_NULL_DATA ? "NULL" : (char*)sch,
                   ind_tbl == SQL_NULL_DATA ? "NULL" : (char*)tbl,
                   ind_col == SQL_NULL_DATA ? "NULL" : (char*)col,
                   ind_dt == SQL_NULL_DATA ? 0 : dataType,
                   ind_tn == SQL_NULL_DATA ? "NULL" : (char*)typeName);
        }
        printf("  Total columns: %d\n", colRowCount);
        if (colRowCount == 0) {
            fprintf(stderr, "FAIL: SQLColumnsW returned 0 columns for test_data\n");
            SQLFreeHandle(SQL_HANDLE_STMT, hStmt);
            SQLDisconnect(hDbc);
            SQLFreeHandle(SQL_HANDLE_DBC, hDbc);
            SQLFreeHandle(SQL_HANDLE_ENV, hEnv);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    /* Test SQLColumnsW with catalog and schema specified */
    printf("\n=== WIDE: SQLColumnsW with catalog=memory, schema=main ===\n");
    ret = SQLColumnsW(hStmt, L"memory", SQL_NTS, L"main", SQL_NTS, L"test_data", SQL_NTS, NULL, 0);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLColumnsW(memory.main.test_data)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        int colRowCount = 0;
        while (1) {
            ret = SQLFetch(hStmt);
            if (ret == SQL_NO_DATA) break;
            if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
                check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLFetch(SQLColumnsW qualified)");
                break;
            }
            colRowCount++;
            SQLCHAR col[128], typeName[128];
            SQLSMALLINT dataType;
            SQLLEN ind_col, ind_dt, ind_tn;
            SQLGetData(hStmt, 4, SQL_C_CHAR, col, sizeof(col), &ind_col);
            SQLGetData(hStmt, 5, SQL_C_SSHORT, &dataType, 0, &ind_dt);
            SQLGetData(hStmt, 6, SQL_C_CHAR, typeName, sizeof(typeName), &ind_tn);
            printf("  col=%s type=%d(%s)\n",
                   ind_col == SQL_NULL_DATA ? "NULL" : (char*)col,
                   ind_dt == SQL_NULL_DATA ? 0 : dataType,
                   ind_tn == SQL_NULL_DATA ? "NULL" : (char*)typeName);
        }
        printf("  Total columns (qualified): %d\n", colRowCount);
        if (colRowCount == 0) {
            fprintf(stderr, "FAIL: SQLColumnsW with catalog/schema returned 0 columns\n");
            SQLFreeHandle(SQL_HANDLE_STMT, hStmt);
            SQLDisconnect(hDbc);
            SQLFreeHandle(SQL_HANDLE_DBC, hDbc);
            SQLFreeHandle(SQL_HANDLE_ENV, hEnv);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    /* Also test a basic SQL query to confirm connection works */
    printf("\n=== Direct SQL test ===\n");
    ret = SQLExecDirectA(hStmt, (SQLCHAR*)"SELECT 42 AS answer", SQL_NTS);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLExecDirect");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLCHAR val[32];
        SQLLEN indicator;
        ret = SQLFetch(hStmt);
        if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
            SQLGetData(hStmt, 1, SQL_C_CHAR, val, sizeof(val), &indicator);
            printf("  SELECT 42 = %s\n", val);
        }
        SQLCloseCursor(hStmt);
    }

    /* Test parameterized queries (SQLPrepare + SQLBindParameter + SQLExecute).
     * This exercises the exact code path Power BI DirectQuery uses.
     * Before the SQL_C_LONG fix, this would fail with:
     *   "Cannot convert C type 4 to Arrow int64" */

    /* Test: LIMIT ? with integer parameter */
    printf("\n=== Parameterized: SELECT * FROM test_data LIMIT ? ===\n");
    SQLCloseCursor(hStmt);
    ret = SQLPrepareA(hStmt, (SQLCHAR*)"SELECT * FROM test_data LIMIT ?", SQL_NTS);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLPrepare(LIMIT ?)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLINTEGER limitVal = 2;
        ret = SQLBindParameter(hStmt, 1, SQL_PARAM_INPUT, SQL_C_LONG,
                               SQL_INTEGER, 0, 0, &limitVal, 0, NULL);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLBindParameter(LIMIT)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: SQLBindParameter for LIMIT failed\n");
            return 1;
        }

        ret = SQLExecute(hStmt);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLExecute(LIMIT ?)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: Parameterized LIMIT query failed\n");
            return 1;
        }

        int rowCount = 0;
        while (SQLFetch(hStmt) == SQL_SUCCESS) rowCount++;
        printf("  Rows returned: %d (expected 2)\n", rowCount);
        if (rowCount != 2) {
            fprintf(stderr, "FAIL: Expected 2 rows, got %d\n", rowCount);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    /* Test: WHERE with string parameter */
    printf("\n=== Parameterized: SELECT * FROM test_data WHERE name = ? ===\n");
    SQLFreeStmt(hStmt, SQL_RESET_PARAMS);
    ret = SQLPrepareA(hStmt, (SQLCHAR*)"SELECT * FROM test_data WHERE name = ?", SQL_NTS);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLPrepare(WHERE name=?)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLCHAR nameVal[] = "bob";
        SQLLEN nameLen = SQL_NTS;
        ret = SQLBindParameter(hStmt, 1, SQL_PARAM_INPUT, SQL_C_CHAR,
                               SQL_VARCHAR, 50, 0, nameVal, sizeof(nameVal), &nameLen);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLBindParameter(name)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: SQLBindParameter for name failed\n");
            return 1;
        }

        ret = SQLExecute(hStmt);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLExecute(WHERE name=?)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: Parameterized WHERE name query failed\n");
            return 1;
        }

        int rowCount = 0;
        SQLCHAR resultName[128];
        SQLLEN ind;
        while (SQLFetch(hStmt) == SQL_SUCCESS) {
            rowCount++;
            SQLGetData(hStmt, 2, SQL_C_CHAR, resultName, sizeof(resultName), &ind);
            printf("  Row %d: name=%s\n", rowCount, resultName);
        }
        printf("  Rows returned: %d (expected 1)\n", rowCount);
        if (rowCount != 1) {
            fprintf(stderr, "FAIL: Expected 1 row, got %d\n", rowCount);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    /* Test: WHERE with integer parameter */
    printf("\n=== Parameterized: SELECT * FROM test_data WHERE id = ? ===\n");
    SQLFreeStmt(hStmt, SQL_RESET_PARAMS);
    ret = SQLPrepareA(hStmt, (SQLCHAR*)"SELECT * FROM test_data WHERE id = ?", SQL_NTS);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLPrepare(WHERE id=?)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLINTEGER idVal = 3;
        ret = SQLBindParameter(hStmt, 1, SQL_PARAM_INPUT, SQL_C_LONG,
                               SQL_INTEGER, 0, 0, &idVal, 0, NULL);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLBindParameter(id)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: SQLBindParameter for id failed\n");
            return 1;
        }

        ret = SQLExecute(hStmt);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLExecute(WHERE id=?)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: Parameterized WHERE id query failed\n");
            return 1;
        }

        int rowCount = 0;
        SQLINTEGER resultId;
        SQLLEN ind;
        while (SQLFetch(hStmt) == SQL_SUCCESS) {
            rowCount++;
            SQLGetData(hStmt, 1, SQL_C_LONG, &resultId, 0, &ind);
            printf("  Row %d: id=%d\n", rowCount, resultId);
        }
        printf("  Rows returned: %d (expected 1)\n", rowCount);
        if (rowCount != 1) {
            fprintf(stderr, "FAIL: Expected 1 row, got %d\n", rowCount);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    /* Test: Multiple parameters */
    printf("\n=== Parameterized: SELECT * FROM test_data WHERE id = ? AND name = ? ===\n");
    SQLFreeStmt(hStmt, SQL_RESET_PARAMS);
    ret = SQLPrepareA(hStmt, (SQLCHAR*)"SELECT * FROM test_data WHERE id = ? AND name = ?", SQL_NTS);
    check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLPrepare(WHERE id=? AND name=?)");
    if (ret == SQL_SUCCESS || ret == SQL_SUCCESS_WITH_INFO) {
        SQLINTEGER idVal = 1;
        SQLCHAR nameVal[] = "alice";
        SQLLEN nameLen = SQL_NTS;
        ret = SQLBindParameter(hStmt, 1, SQL_PARAM_INPUT, SQL_C_LONG,
                               SQL_INTEGER, 0, 0, &idVal, 0, NULL);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLBindParameter(id)");
        ret = SQLBindParameter(hStmt, 2, SQL_PARAM_INPUT, SQL_C_CHAR,
                               SQL_VARCHAR, 50, 0, nameVal, sizeof(nameVal), &nameLen);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLBindParameter(name)");

        ret = SQLExecute(hStmt);
        check_error(ret, SQL_HANDLE_STMT, hStmt, "SQLExecute(WHERE id=? AND name=?)");
        if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
            fprintf(stderr, "FAIL: Multi-parameter query failed\n");
            return 1;
        }

        int rowCount = 0;
        while (SQLFetch(hStmt) == SQL_SUCCESS) rowCount++;
        printf("  Rows returned: %d (expected 1)\n", rowCount);
        if (rowCount != 1) {
            fprintf(stderr, "FAIL: Expected 1 row, got %d\n", rowCount);
            return 1;
        }
        SQLCloseCursor(hStmt);
    }

    printf("\nAll tests passed!\n");

    SQLFreeHandle(SQL_HANDLE_STMT, hStmt);
    SQLDisconnect(hDbc);
    SQLFreeHandle(SQL_HANDLE_DBC, hDbc);
    SQLFreeHandle(SQL_HANDLE_ENV, hEnv);
    printf("Done.\n");
    return 0;
}
