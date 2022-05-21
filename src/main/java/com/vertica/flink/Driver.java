/*
 * Copyright (c) DingQiang Liu(dingqiangliu@gmail.com), 2012 - 2022
 */

package com.vertica.flink;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/** JDBC Driver with batch Upset/Merge. */
public class Driver extends com.vertica.jdbc.Driver {
    public static Pattern regMergeInfo =
            Pattern.compile(
                    "\\s*MERGE\\s*INTO\\s*(\\w*)\\s*.*USING\\s*.*\\s*SELECT\\s*(.*)\\s*FROM\\s*(\\w*).*\\s*ON\\s*(.*)\\s*WHEN\\s*MATCHED\\s*.*");

    @Override
    public Connection connect(String url, Properties info) throws SQLException {
        return (Connection)
                Proxy.newProxyInstance(
                        Connection.class.getClassLoader(),
                        new Class[] {Connection.class},
                        new InvocationHandler() {
                            private Connection conn = Driver.super.connect(url, info);

                            @Override
                            public Object invoke(Object proxy, Method methd, Object[] args)
                                    throws Throwable {
                                if ("prepareStatement".equals(methd.getName())
                                        && args.length == 1) {
                                    // Connection.prepareStatement(java.lang.String sql)
                                    String sql = (String) args[0];
                                    return preparedStatement4Upset(conn, sql);
                                } else {
                                    return methd.invoke(conn, args);
                                }
                            }
                        });
    }

    /**
     * translate batch Upset/Merge to batch Insert & regular Merge.
     *
     * @param conn JDBC connection
     * @param sql prepared query with placeholders "?"
     * @return prepared statement after translation
     * @throws SQLException
     */
    private static PreparedStatement preparedStatement4Upset(Connection conn, String sql)
            throws SQLException {
        String regularSQL = sql.replaceAll("\\?\\s*", ""); // remove placeholders "?"
        Matcher matcher = regMergeInfo.matcher(regularSQL);
        Boolean isUpset = matcher.find();

        String tgtTable = (!isUpset) ? null : matcher.group(1);
        String tmpTable = (!isUpset) ? null : tgtTable + "__";
        String tgtColumns = (!isUpset) ? null : matcher.group(2);
        String srcTable = (!isUpset) ? null : matcher.group(3);

        // remove "(" and ")"
        String matchCondition = (!isUpset) ? null : matcher.group(4).replaceAll("[()]", "");
        String uniqueKeyColumns =
                (!isUpset)
                        ? null
                        : Arrays.stream(matchCondition.split("and"))
                                .map(eq -> eq.split("\\s*=")[0].replaceAll("^\\s*\\w*\\.", ""))
                                .collect(Collectors.joining(", "));

        String sqlCreateTempTable =
                (!isUpset)
                        ? null
                        : "CREATE LOCAL TEMP TABLE IF NOT EXISTS "
                                + tmpTable
                                + " ON COMMIT PRESERVE ROWS AS (SELECT "
                                + tgtColumns
                                + " FROM "
                                + tgtTable
                                + " limit 0) ORDER BY "
                                + uniqueKeyColumns
                                + " SEGMENTED BY HASH("
                                + uniqueKeyColumns
                                + ") ALL NODES";
        String sqlBatchInsert =
                (!isUpset)
                        ? null
                        : "INSERT INTO "
                                + tmpTable
                                + "("
                                + tgtColumns
                                + ") VALUES ("
                                + Arrays.stream(tgtColumns.split(","))
                                        .map(e -> "?")
                                        .collect(Collectors.joining(", "))
                                + ")";
        String sqlMergeInto = (!isUpset) ? null : regularSQL.replaceAll(srcTable, tmpTable);
        String sqlCleanTempTable = (!isUpset) ? null : "DELETE FROM " + tmpTable;

        if (isUpset) {
            conn.createStatement().execute(sqlCreateTempTable);
        }

        return (PreparedStatement)
                Proxy.newProxyInstance(
                        PreparedStatement.class.getClassLoader(),
                        new Class[] {PreparedStatement.class},
                        new InvocationHandler() {
                            private PreparedStatement stat =
                                    conn.prepareStatement(isUpset ? sqlBatchInsert : sql);

                            @Override
                            public Object invoke(Object proxy, Method methd, Object[] args)
                                    throws Throwable {
                                Object ret = methd.invoke(stat, args);
                                if ("executeBatch".equals(methd.getName())) {
                                    // PreparedStatement.executeBatch()
                                    if (isUpset) {
                                        conn.createStatement()
                                                .execute(sqlMergeInto + ";" + sqlCleanTempTable);
                                    }
                                }
                                return ret;
                            }
                        });
    }
}
