# Vertica Connector for Flink

This project is a plugin of  [**Flink JDBC SQL Connector**](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/jdbc/) to allow reading data from Vertica by batch,  writing data into Vertica from streams of  [**Flink CDC Connectors**](https://nightlies.apache.org/flink/flink-cdc-docs-stable/docs/connectors/legacy-flink-cdc-sources/overview/) for other databases like PostgreSQL/MySQL/Oracle/SQL Server and other streams or batch sources.

![The architecture of Flink](https://flink.apache.org/img/flink-home-graphic.png)

![The architecture of Flink CDC](https://nightlies.apache.org/flink/flink-cdc-docs-stable/fig/cdc-flow.png)

## Examples

### Write data from MySQL to Vertica by batch

This [demo](./demos/testBatchMySQL2Vertica/testBatchMySQL2Vertica.sh) can be easily run with [docker-compose](https://docs.docker.com/compose/). Here is the key part:

```SQL
CREATE TABLE test_flink_orders (
    orderID INT
    , custName VARCHAR(50)
    , fAmount FLOAT
    , dAmount DOUBLE
    , deAmount DECIMAL(17,4)
    , nAmount DECIMAL(17,4)
    , bVIP BOOLEAN
    , dCreate DATE
    , tCreate TIME(6)
    , tzCreate TIME(6)
    , dtCreate TIMESTAMP(6)
    , dtzCreate TIMESTAMP(6)
    , binPhoto BYTES
    , PRIMARY KEY (orderID) NOT ENFORCED
) WITH (
    'connector' = 'jdbc'
    , 'url' = 'jdbc:mysql://${yourMySQLServer}:3306/${yourMySQLDB}?
    , 'username' = '${yourUsername}'
    , 'password' = '${yourPassword}'
    , 'scan.fetch-size' = '10000'
    , 'table-name' = 'test_flink_orders'
);

CREATE TABLE test_flink_orders_target (
    orderID INT
    , custName VARCHAR(50)
    , fAmount FLOAT
    , dAmount DOUBLE
    , deAmount DECIMAL(17,4)
    , nAmount DECIMAL(17,4)
    , bVIP BOOLEAN
    , dCreate DATE
    , tCreate TIME(6)
    , tzCreate TIME(6)
    , dtCreate TIMESTAMP(6)
    , dtzCreate TIMESTAMP(6)
    , binPhoto BYTES
    , PRIMARY KEY (orderID) NOT ENFORCED
) WITH (
    'connector' = 'jdbc'
    , 'url' = 'jdbc:vertica://${yourVerticaServer}:5433/${yourVerticaDBName}'
    , 'username' = '${yourUsername}'
    , 'password' = '${yourPassword}'
    , 'sink.buffer-flush.max-rows' = '10000'
    , 'table-name' = 'test_flink_orders_target'
);

INSERT INTO test_flink_orders_target
SELECT 
    orderID
    , custName 
    , fAmount
    , dAmount
    , deAmount
    , nAmount
    , bVIP
    , dCreate
    , tCreate
    , tzCreate
    , dtCreate
    , dtzCreate
    , binPhoto
FROM test_flink_orders;
```

### Ingesting changes of MySQL to Vertica in real-time

This [demo](./demos/testCDCMySQL2Vertica/testCDCMySQL2Vertica.sh) can be easily run with [docker-compose](https://docs.docker.com/compose/). Here is its key part:

```SQL
CREATE TABLE test_flink_orders (
    orderID INT
    , custName VARCHAR(50)
    , fAmount FLOAT
    , dAmount DOUBLE
    , deAmount DECIMAL(17,4)
    , nAmount DECIMAL(17,4)
    , bVIP BOOLEAN
    , dCreate DATE
    , tCreate TIME(6)
    , tzCreate TIME(6)
    , dtCreate TIMESTAMP(6)
    , dtzCreate TIMESTAMP(6)
    , binPhoto BYTES
    , PRIMARY KEY (orderID) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc'
    , 'hostname' = 'localhost'
    , 'port' = '3306'
    , 'jdbc.properties.serverTimezone' = '${TZ}'
    , 'username' = 'liudq'
    , 'password' = 'mysql'
    , 'database-name' = 'liudq'
    , 'table-name' = 'test_flink_orders'
);

CREATE TABLE test_flink_orders_target (
    orderID INT
    , custName VARCHAR(50)
    , fAmount FLOAT
    , dAmount DOUBLE
    , deAmount DECIMAL(17,4)
    , nAmount DECIMAL(17,4)
    , bVIP BOOLEAN
    , dCreate DATE
    , tCreate TIME(6)
    , tzCreate TIME(6)
    , dtCreate TIMESTAMP(6)
    , dtzCreate TIMESTAMP(6)
    , binPhoto BYTES
    , PRIMARY KEY (orderID) NOT ENFORCED
) WITH (
    'connector' = 'jdbc'
    , 'url' = 'jdbc:vertica://${yourVerticaServer}:5433/${yourVerticaDBName}'
    , 'username' = '${yourUsername}'
    , 'password' = '${yourPassword}'
    , 'sink.buffer-flush.max-rows' = '10000'
    , 'table-name' = 'test_flink_orders_target'
);

INSERT INTO test_flink_orders_target
SELECT 
    orderID
    , custName 
    , fAmount
    , dAmount
    , deAmount
    , nAmount
    , bVIP
    , dCreate
    , tCreate
    , tzCreate
    , dtCreate
    , dtzCreate
    , binPhoto
FROM test_flink_orders;
```

## Installation

At first, you need setup [Flink](https://flink.apache.org/) cluster and its [JDBC SQL Connector](https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/jdbc/), and [CDC Connectors](https://nightlies.apache.org/flink/flink-cdc-docs-stable/docs/connectors/overview/) optionally.

You can [download](https://github.com/dingqiangliu/vertica-flink-connector/releases/latest) the latest version of **`vertica-flink-connector_${FLINK_VERSON}-*.jar`**, or build it from source code of this project, and just put it in **${FLINK_HOME}/lib** and restart you cluster..

### [Optional] Build from source code

#### Requirements

- Java 11+
- Maven 3.3+


You will get **`vertica-flink-connector_${FLINK_VERSON}-*.jar`** under [**target/**] directory after correctly running following command under top of source code tree.

``` BASH
mvn -DskipTests=true clean package
```

