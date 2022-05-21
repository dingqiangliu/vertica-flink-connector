/*
 * Copyright (c) DingQiang Liu(dingqiangliu@gmail.com), 2012 - 2022
 */

package com.vertica.flink;

import org.apache.flink.connector.jdbc.converter.AbstractJdbcRowConverter;
import org.apache.flink.table.types.logical.LogicalType;
import org.apache.flink.table.types.logical.RowType;

/**
 * Runtime converter that responsible to convert between JDBC object and Flink internal object for
 * Vertica.
 */
public class VerticaRowConverter extends AbstractJdbcRowConverter {

    private static final long serialVersionUID = 1L;

    public VerticaRowConverter(RowType rowType) {
        super(rowType);
    }

    @Override
    public JdbcDeserializationConverter createInternalConverter(LogicalType type) {
        switch (type.getTypeRoot()) {
            case TINYINT:
                return val -> val instanceof Long ? ((Long) val).byteValue() : val;
            case SMALLINT:
                return val -> val instanceof Long ? ((Long) val).shortValue() : val;
            case INTEGER:
            case BIGINT:
                return val -> val instanceof Long ? ((Long) val).intValue() : val;
            case FLOAT:
                return val -> val instanceof Double ? ((Double) val).floatValue() : val;
            default:
                return super.createInternalConverter(type);
        }
    }

    @Override
    public String converterName() {
        return "Vertica";
    }
}
