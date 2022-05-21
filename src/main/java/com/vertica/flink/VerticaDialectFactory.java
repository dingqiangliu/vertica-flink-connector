/*
 * Copyright (c) DingQiang Liu(dingqiangliu@gmail.com), 2012 - 2022
 */

package com.vertica.flink;

import org.apache.flink.annotation.Internal;
import org.apache.flink.connector.jdbc.dialect.JdbcDialect;
import org.apache.flink.connector.jdbc.dialect.JdbcDialectFactory;

/** Factory for {@link VerticaDialect}. */
@Internal
public class VerticaDialectFactory implements JdbcDialectFactory {
    @Override
    public boolean acceptsURL(String url) {
        return url.startsWith("jdbc:vertica:");
    }

    @Override
    public JdbcDialect create() {
        return new VerticaDialect();
    }
}
