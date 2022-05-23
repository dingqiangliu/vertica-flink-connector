#!/usr/bin/env bash

SRC_DB="demodb"
SRC_DB_HOST="localhost"
SRC_DB_USER="demouser"
SRC_DB_PWD="demopwd"
SRC_DB_ROOT_PWD="demopwd"

TGT_DB="VMart"
TGT_DB_HOST="localhost"
TGT_DB_USER="dbadmin"
TGT_DB_PWD="demopwd"

SRC_INIT_ROWCOUNT=500000

JOB_NAME="insert-into_default_catalog.default_database.test_flink_orders_target"


if test -z "${FLINK_HOME}" -o -z "${MYSQL}" -o -z "${VSQL}" ; then
  if which docker docker-compose > /dev/null ; then
    # docker deployment
    echo "Notice: environment variables [FLINK_HOME] [MYSQL] [VSQL] not set, use containers"
    SRC_DB_HOST="mysql"
    TGT_DB_HOST="vertica"
    scriptDir="$(cd $(dirname ${0}); pwd)"
    DOCKER_COMPOSE="docker-compose -f ${scriptDir}/docker-compose.yml"

    # Note: 
    #   "mysql" is 5 times quicker than "docker exec mysql", 
    #    and "docker exec mysql" is 7 times quicker than "docker-exec exec mysql" !

    #FLINK_HOME="${DOCKER_COMPOSE} exec -T jobmanager /opt/flink"
    FLINK_HOME="docker exec testbatchmysql2vertica_jobmanager_1 /opt/flink"

    #MYSQL="${DOCKER_COMPOSE} exec -e MYSQL_PWD="${SRC_DB_PWD}" -T mysql mysql -u${SRC_DB_USER} -D${SRC_DB}"
    if which mysql > /dev/null ; then
      MYSQL_PWD="${SRC_DB_PWD}"
      MYSQL="mysql --protocol=TCP -u${SRC_DB_USER} -D${SRC_DB}"
    else
      MYSQL="docker exec -e MYSQL_PWD="${SRC_DB_PWD}" testbatchmysql2vertica_mysql_1 mysql -u${SRC_DB_USER} -D${SRC_DB}"
    fi

    #MYSQL_ROOT="${DOCKER_COMPOSE} exec -e MYSQL_PWD="${SRC_DB_ROOT_PWD}" -T mysql mysql -uroot"
    if which mysql > /dev/null ; then
      MYSQL_ROOT="mysql --protocol=TCP -uroot -p${SRC_DB_ROOT_PWD}"
    else
      MYSQL_ROOT="docker exec -e MYSQL_PWD="${SRC_DB_ROOT_PWD}" testbatchmysql2vertica_mysql_1 mysql -uroot"
    fi

    #VSQL="${DOCKER_COMPOSE} exec -T vertica /opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB} -i"
    if test -e /opt/vertica/bin/vsql ; then
      VSQL="/opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB}"
    else
      VSQL="docker exec testbatchmysql2vertica_vertica_1 /opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB} -i"
    fi
  elif ! which docker docker-compose > /dev/null ; then
    echo "environment variables [FLINK_HOME] [MYSQL] [VSQL] not set, no docker & docker-compose installed!" >&2 
    echo "please manually setup environment variables [FLINK_HOME] [MYSQL] [VSQL] according to your Flink/MySQL/Vertica," >&2 
    echo "or install no docker & docker-compose with command "sudo apt install docker.io docker-compose" " >&2 
    exit 1
  fi
else
  # native install
  MYSQL_HOST="${SRC_DB_HOST}"
  MYSQL_PWD="${SRC_DB_PWD}"
  MYSQL="mysql --protocol=TCP -h${SRC_DB_HOST} -u${SRC_DB_USER} -D${SRC_DB}"
  MYSQL_ROOT="sudo mysql"

  VSQL="/opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB}"
fi


echo
echo "======================================================="
echo "Preparing source table..."
echo "======================================================="

# make deployment ready
if test -n "${DOCKER_COMPOSE}" ; then
  # docker deployment
  if ! ${DOCKER_COMPOSE} ps | grep -q "Up" ; then
    echo "Notice: this step maybe need some time to pull & build docker images at the first time ..."
    ${DOCKER_COMPOSE} up -d
  fi
else
  # native install
  # sudo apt install -y mysql-server mysql-client
  # sudo systemctl start mysql
  echo
fi

# make sure MySQL is up
echo "$(date +%H:%M:%S) waiting MySQL up ..."
for ((i=0; i<100; i++)) ; do
  test "1" = "$(${MYSQL_ROOT} -N <<< 'SELECT 1' 2>/dev/null)" && break
  sleep 3;
done

# make sure Vertica is up
echo "$(date +%H:%M:%S) waiting Vertica up ..."
for ((i=0; i<100; i++)) ; do
  test "1" = "$(${VSQL} -Aqt -c 'select 1' 2>/dev/null)" && break
  sleep 3;
done


${MYSQL_ROOT} -v -t <<-EOF
  CREATE USER IF NOT EXISTS ${SRC_DB_USER} identified by '${SRC_DB_PWD}';
  CREATE DATABASE IF NOT EXISTS ${SRC_DB};
  GRANT ALL ON ${SRC_DB}.* TO ${SRC_DB_USER};

  /* for load data local infile */
  SET GLOBAL local_infile = 'ON';

  /* for queries in history */
  SET GLOBAL log_output = 'TABLE'; SET GLOBAL general_log = 'ON';

  /* time zone */
  SET GLOBAL time_zone = '${TZ}';
  SHOW GLOBAL VARIABLES LIKE '%time_zone%';
EOF


${MYSQL} -v -t <<-EOF
  DROP TABLE IF EXISTS test_flink_orders;
  CREATE TABLE test_flink_orders(
    orderID INT NOT NULL PRIMARY KEY
    , custName VARCHAR(50) DEFAULT (CONCAT('cust-', orderID))
    , fAmount FLOAT DEFAULT (CAST(orderID + 0.12345 AS FLOAT))
    , dAmount DOUBLE DEFAULT (CAST(orderID + 0.123456789012345 AS DOUBLE))
    , deAmount DECIMAL(17,4) DEFAULT (CAST(orderID + 0.1234 AS DECIMAL(17,4)))
    , nAmount NUMERIC(17,4) DEFAULT (CAST(orderID + 0.1234 AS DECIMAL(17,4)))
    , bVIP BOOLEAN DEFAULT (orderID % 2)
    , dCreate DATE DEFAULT (ADDDATE('2006-09-09', (orderID-1) % 365))
    , tCreate TIME(6) DEFAULT (DATE_ADD(TIME '00:00:00.123456', INTERVAL (orderID-1) % 86400 SECOND))
    , tzCreate TIME(6) /* WITH TIME ZONE */ DEFAULT (DATE_ADD(TIME '00:00:00.123456', INTERVAL (orderID-1) % 86400 SECOND))
    , dtCreate TIMESTAMP(6) DEFAULT (ADDDATE('2006-09-09 00:00:00.123456', (orderID-1) % 365)) 
    , dtzCreate TIMESTAMP(6) /* WITH TIME ZONE */ DEFAULT (ADDDATE('2006-09-09 00:00:00.123456', (orderID-1) % 365))
    , binPhoto VARBINARY(2) DEFAULT (BINARY (CHAR(orderID % 365)))
  );

  TRUNCATE TABLE test_flink_orders;
EOF


seq 1 ${SRC_INIT_ROWCOUNT} > /tmp/tmp.dat
${MYSQL} -v -t --local-infile <<-EOF
  /*SET GLOBAL local_infile = 'ON';*/
  LOAD DATA LOCAL INFILE '/tmp/tmp.dat' INTO TABLE test_flink_orders (orderID);

  SELECT COUNT(*) FROM test_flink_orders;
EOF
rm /tmp/tmp.dat


echo
echo "======================================================="
echo "Preparing target table..."
echo "======================================================="

${VSQL} -e <<-EOF
  DROP TABLE IF EXISTS test_flink_orders_target;
  CREATE TABLE test_flink_orders_target(
    orderID INT NOT NULL PRIMARY KEY
    , custName VARCHAR(50)
    , fAmount FLOAT
    , dAmount DOUBLE PRECISION
    , deAmount DECIMAL(17,4)
    , nAmount NUMERIC(17,4)
    , bVIP BOOLEAN
    , dCreate DATE
    , tCreate TIME(6)
    , tzCreate TIME(6) WITH TIME ZONE
    , dtCreate TIMESTAMP(6)
    , dtzCreate TIMESTAMP(6) WITH TIME ZONE
    , binPhoto VARBINARY(2)
  );

  TRUNCATE TABLE test_flink_orders_target;

  SELECT COUNT(*) FROM test_flink_orders_target;
EOF


function getJobDDL ()
{
  # Note: 
  # 1. no TIME WITH TIME ZONE type
  # 2. no TIMESTAMP WITH TIME ZONE type
  # 3. there is no subsecond part or java.sql.Time
  # 4. 'serverTimezone' parameter of MySQL JDBC driver can not use 'CST', the default system_time_zone value in China,
  #   which will cause Flink SQL gets diffent TIME value, normally 14:00:00 in China,
  #   because 'CST' is looked as "Central Standard Time (USA) UT-6:00", not "China Standard Time UT+8:00" as expected.

cat <<-EOF
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
     --'driver' = 'com.mysql.cj.jdbc.Driver'
     , 'url' = 'jdbc:mysql://${SRC_DB_HOST}:3306/${SRC_DB}?serverTimezone=${TZ}'
     , 'username' = '${SRC_DB_USER}'
     , 'password' = '${SRC_DB_PWD}'
     , 'scan.fetch-size' = '10000'
     -- , 'scan.partition.num' = '2'
     -- , 'scan.partition.column' = 'dCreate'
     -- , 'scan.partition.lower-bound' = '20060909'
     -- , 'scan.partition.upper-bound' = '20070908'
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
     -- , 'driver' = 'com.vertica.flink.Driver'
     , 'url' = 'jdbc:vertica://${TGT_DB_HOST}:5433/${TGT_DB}'
     , 'username' = '${TGT_DB_USER}'
     , 'password' = '${TGT_DB_PWD}'
     , 'sink.buffer-flush.max-rows' = '10000'
     -- , 'sink.parallelism' = '2'
     , 'table-name' = 'test_flink_orders_target'
  );
EOF
}


echo
echo "======================================================="
echo "Submiting job..."
echo "======================================================="

function getJobSQL ()
{
cat <<-EOF
  SET 'sql-client.execution.result-mode' = 'tableau';

  $(getJobDDL)

  SHOW TABLES;

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
EOF
}

${FLINK_HOME}/bin/sql-client.sh embedded -u "$(getJobSQL)"



function get_source_row_count ()
{
  ${MYSQL} -N <<< 'SELECT COUNT(*) FROM test_flink_orders' 2>/dev/null
}


function get_target_row_count ()
{
  ${VSQL} -Aqtc 'SELECT COUNT(*) FROM test_flink_orders_target'
}


echo
echo "======================================================="
echo "Waiting job finished..."
echo "======================================================="

while ${FLINK_HOME}/bin/flink list -r | grep -q "${JOB_NAME}" ; do 
  echo "$(date -Iseconds) [status] source table rows = $(get_source_row_count)" \
       ", target table rows = $(get_target_row_count)"
  sleep 2
done


echo
echo "======================================================="
echo "Comparing data in Flink SQL..."
echo "======================================================="

function getSearchSQL ()
{
cat <<-EOF
  SET 'sql-client.execution.result-mode' = 'tableau';

  $(getJobDDL)

  SHOW TABLES;

  SELECT * FROM test_flink_orders order by orderID limit 10;

  SELECT * FROM test_flink_orders_target order by orderID limit 10;
EOF
}

${FLINK_HOME}/bin/sql-client.sh embedded -u "$(getSearchSQL)"


echo
echo "======================================================="
echo "Comparing data in databases..."
echo "======================================================="

${MYSQL} -v -t <<-EOF
  SELECT COUNT(*) FROM test_flink_orders;

  SELECT * FROM test_flink_orders ORDER BY orderID limit 10;
EOF

${VSQL} -e <<-EOF
  SELECT COUNT(*) FROM test_flink_orders_target;

  SELECT * FROM test_flink_orders_target ORDER BY orderID limit 10;
EOF

