FROM apache/flink:1.18.0-scala_2.12-java11

# Download connector libraries
RUN wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/org/apache/flink/flink-connector-jdbc/3.1.2-1.18/flink-connector-jdbc-3.1.2-1.18.jar; \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/ververica/flink-sql-connector-mysql-cdc/3.0.1/flink-sql-connector-mysql-cdc-3.0.1.jar; \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/ververica/flink-sql-connector-postgres-cdc/3.0.1/flink-sql-connector-postgres-cdc-3.0.1.jar; \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/ververica/flink-sql-connector-oracle-cdc/3.0.1/flink-sql-connector-oracle-cdc-3.0.1.jar; \
    wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/ververica/flink-sql-connector-sqlserver-cdc/3.0.1/flink-sql-connector-sqlserver-cdc-3.0.1.jar; \
    # Notice: following JDBC drivers already exist in *-cdc-*.jar
    #wget -P /opt/flink/lib/ https://repo.maven.apache.org/maven2/mysql/mysql-connector-java/8.0.29/mysql-connector-java-8.0.29.jar; \
    #wget -P /opt/flink/lib/ https://jdbc.postgresql.org/download/postgresql-42.3.5.jar; \
    #wget -P /opt/flink/lib/ https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc8/21.5.0.0/ojdbc8-21.5.0.0.jar; \
    wget -P /opt/flink/lib/ https://github.com/dingqiangliu/vertica-flink-connector/releases/download/0.1.0/vertica-flink-connector_3.1.2-1.18-0.1.0.jar;

RUN #echo "execution.checkpointing.interval: 3s" >> /opt/flink/conf/flink-conf.yaml; \
    #echo "pipeline.object-reuse: true" >> /opt/flink/conf/flink-conf.yaml; \
    #echo "pipeline.time-characteristic: EventTime" >> /opt/flink/conf/flink-conf.yaml; \
    #echo "state.backend: filesystem" >> /opt/flink/conf/flink-conf.yaml; \
    #echo "state.checkpoints.dir: file:///tmp" >> /opt/flink/conf/flink-conf.yaml; \
    #echo "state.savepoints.dir: file:///tmp" >> /opt/flink/conf/flink-conf.yaml; \
    sed -i -E 's/(^taskmanager\.numberOfTaskSlots:).*$/\1 4/g' /opt/flink/conf/flink-conf.yaml; \
    sed -i -E 's/(^taskmanager\.memory\.process\.size:).*$/\1 4096m/g' /opt/flink/conf/flink-conf.yaml;

