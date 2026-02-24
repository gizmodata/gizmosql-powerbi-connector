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

    SQLFreeHandle(SQL_HANDLE_STMT, hStmt);
    SQLDisconnect(hDbc);
    SQLFreeHandle(SQL_HANDLE_DBC, hDbc);
    SQLFreeHandle(SQL_HANDLE_ENV, hEnv);
    printf("\nDone.\n");
    return 0;
}
