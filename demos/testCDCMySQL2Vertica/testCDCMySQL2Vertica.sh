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

SRC_INIT_ROWCOUNT=10000
TGT_INIT_ROWCOUNT=0
INC_ROWCOUNT=200
UPDATE_PCT=10
DELETE_PCT=10

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
    FLINK_HOME="docker exec testcdcmysql2vertica_jobmanager_1 /opt/flink"

    #MYSQL="${DOCKER_COMPOSE} exec -e MYSQL_PWD="${SRC_DB_PWD}" -T mysql mysql -u${SRC_DB_USER} -D${SRC_DB}"
    if which mysql > /dev/null ; then
      MYSQL_PWD="${SRC_DB_PWD}"
      MYSQL="mysql --protocol=TCP -u${SRC_DB_USER} -D${SRC_DB}"
    else
      MYSQL="docker exec -e MYSQL_PWD="${SRC_DB_PWD}" testcdcmysql2vertica_mysql_1 mysql -u${SRC_DB_USER} -D${SRC_DB}"
    fi

    #MYSQL_ROOT="${DOCKER_COMPOSE} exec -e MYSQL_PWD="${SRC_DB_ROOT_PWD}" -T mysql mysql -uroot"
    if which mysql > /dev/null ; then
      MYSQL_ROOT="mysql --protocol=TCP -uroot -p${SRC_DB_ROOT_PWD}"
    else
      MYSQL_ROOT="docker exec -e MYSQL_PWD="${SRC_DB_ROOT_PWD}" testcdcmysql2vertica_mysql_1 mysql -uroot"
    fi

    #VSQL="${DOCKER_COMPOSE} exec -T vertica /opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB} -i"
    if test -e /opt/vertica/bin/vsql ; then
      VSQL="/opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB}"
    else
      VSQL="docker exec testcdcmysql2vertica_vertica_1 /opt/vertica/bin/vsql -U ${TGT_DB_USER} -w ${TGT_DB_PWD} -d ${TGT_DB} -i"
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


function init ()
{
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

    /* for CDC */
    GRANT SELECT, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${SRC_DB_USER}';
    SHOW VARIABLES LIKE 'log_bin';
    SHOW GLOBAL VARIABLES LIKE 'binlog%';

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
    LOAD DATA LOCAL INFILE '/tmp/tmp.dat' INTO TABLE test_flink_orders (orderID); 
  
    SELECT count(*) FROM test_flink_orders;
EOF
  rm /tmp/tmp.dat
  
  
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

    SELECT count(*) FROM test_flink_orders_target;
EOF

  TGT_INIT_ROWCOUNT=0
}


function getJobSQL ()
{
  # Note: 
  # 1. no TIME WITH TIME ZONE type
  # 2. no TIMESTAMP WITH TIME ZONE type
  # 3. there is no subsecond part or java.sql.Time
  # 4. 'serverTimezone' parameter of MySQL JDBC driver can not use 'CST', the default system_time_zone value in China,
  #   which will cause Flink SQL gets diffent TIME value, normally 14:00:00 in China,
  #   because 'CST' is looked as "Central Standard Time (USA) UT-6:00", not "China Standard Time UT+8:00" as expected.

cat <<-EOF
  SET 'sql-client.execution.result-mode' = 'tableau';

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
     , 'hostname' = '${SRC_DB_HOST}'
     , 'port' = '3306'
     , 'jdbc.properties.serverTimezone' = '${TZ}'
     , 'username' = '${SRC_DB_USER}'
     , 'password' = '${SRC_DB_PWD}'
     , 'database-name' = '${SRC_DB}'
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


function start_job ()
{
  if ${FLINK_HOME}/bin/flink list -r | grep -q "${JOB_NAME}" ; then
    echo "Job is already running!" >&2
    exit 1
  fi

  ${FLINK_HOME}/bin/sql-client.sh embedded -u "$(getJobSQL)"
}


function stop_job ()
{
  if ! ${FLINK_HOME}/bin/flink list -r | grep -q "${JOB_NAME}" ; then
    echo "No job is running!" >&2
    exit 1
  fi

  ${FLINK_HOME}/bin/flink list -r \
    | grep "${JOB_NAME}" | awk '{print $4}' \
    | xargs -i ${FLINK_HOME}/bin/flink stop --savepointPath /tmp/ {}
}


function resume_job ()
{
  if ${FLINK_HOME}/bin/flink list -r | grep -q "${JOB_NAME}" ; then
    echo "Job is running!" >&2
    exit 1
  fi

  savepointPath="file:$(ls -dt /tmp/savepoint-* | head -1)"
  if [ -z "${savepointPath}" ] ; then
    echo "No savepoint found!" >&2
    exit 1
  fi

  ${FLINK_HOME}/bin/sql-client.sh embedded -u "$(echo "SET execution.savepoint.path=${savepointPath};"; getJobSQL)"
}


function cancel_job ()
{
  if ! ${FLINK_HOME}/bin/flink list -r | grep -q "${JOB_NAME}" ; then
    echo "No job is running!" >&2
    exit 1
  fi

  ${FLINK_HOME}/bin/flink list -r | grep "${JOB_NAME}" | awk '{print $4}' | xargs -i ${FLINK_HOME}/bin/flink cancel {}
}


function get_source_row_count ()
{
  ${MYSQL} -N <<< 'SELECT count(*) FROM test_flink_orders' 2>/dev/null
}


function get_target_row_count ()
{
  ${VSQL} -Aqtc 'SELECT COUNT(*) FROM test_flink_orders_target' 2>/dev/null
}


function gen_data ()
{
  # gen model: UPDATE UPDATE_PCT%, DELETE DELETE_PCT%, INSERT (100+DELETE_PCT)%
  SRC_INIT_ROWCOUNT="$(get_source_row_count)"
  # waiting BASE sync
  echo "$(date +%H:%M:%S) waiting BASE sync to rows: ${SRC_INIT_ROWCOUNT} ..."
  while test "$((TGT_INIT_ROWCOUNT+$(get_target_row_count)))" -lt "${SRC_INIT_ROWCOUNT}" ; do 
    sleep 1
  done
  
  UpRows="$((INC_ROWCOUNT*UPDATE_PCT/100))"
  DelRows="$((INC_ROWCOUNT*DELETE_PCT/100))"
  UpDelRows="$((UpRows+DelRows))"

  # INSERT incremental 1, UpDelRows
  for i in $(seq 1 ${UpDelRows}) ; do
    orderID=$((SRC_INIT_ROWCOUNT + i))
    ${MYSQL} -N <<< "INSERT INTO test_flink_orders(orderID) VALUES(${orderID})"
  done
  # waiting INSERT incremental 1
  echo "$(date +%H:%M:%S) waiting INSERT incremental 1, related rows: ${UpDelRows} ..."
  while test "$((TGT_INIT_ROWCOUNT+$(get_target_row_count)))" -lt "$((SRC_INIT_ROWCOUNT+UpDelRows))" ; do 
    sleep 1
  done
  
  # UPDATE incremental, UpRows
  ${MYSQL} -N <<< "UPDATE test_flink_orders SET custName = concat(custName, '-modified') WHERE orderID>${SRC_INIT_ROWCOUNT} AND orderID<=$((SRC_INIT_ROWCOUNT+UpRows))"
  
  # DELETE incremental, DelRows
  ${MYSQL} -N <<< "DELETE FROM test_flink_orders WHERE orderID>$((SRC_INIT_ROWCOUNT+UpRows)) AND orderID<=$((SRC_INIT_ROWCOUNT+UpDelRows))"

  # waiting UPDATE + DETELE incremental
  echo "$(date +%H:%M:%S) waiting UPDATE + DETELE incremental, related rows: ${UpDelRows} ..."
  while test "$((TGT_INIT_ROWCOUNT+$(get_target_row_count)))" -ne "$((SRC_INIT_ROWCOUNT+UpRows))" ; do 
    sleep 1
  done
  
  # INSERT incremental 2, INC_ROWCOUNT-UpRows
  for i in $(seq $((UpRows+1)) ${INC_ROWCOUNT}) ; do
    orderID=$((SRC_INIT_ROWCOUNT + i))
    ${MYSQL} -N <<< "INSERT INTO test_flink_orders(orderID) VALUES(${orderID})"
  done
  # waiting INSERT incremental 2
  echo "$(date +%H:%M:%S) waiting INSERT incremental 2, related rows: $((INC_ROWCOUNT-UpRows)) ..."
  while test "$((TGT_INIT_ROWCOUNT+$(get_target_row_count)))" -lt "$((SRC_INIT_ROWCOUNT+INC_ROWCOUNT))" ; do 
    sleep 1
  done
}


function start_gen ()
{
  while true; do
    SRC_INIT_ROWCOUNT="$(get_source_row_count)"
    TGT_INIT_ROWCOUNT="$((SRC_INIT_ROWCOUNT-$(get_target_row_count)))"
    gen_data &
    wait
  done
}


function stop_gen ()
{
  ps -ef | grep -e "${0}\s*.*\s*start_gen" | grep -v grep | awk '{print $2}' | xargs kill -SIGTERM
}


function mon_finish ()
{
  echo
  echo "======================================================="
  echo "Activities in target table"
  echo "======================================================="

  dtMonEnd="$(date -Iseconds)"
  ${VSQL} -e <<-EOF
    SELECT request FROM dc_requests_issued
        WHERE time>='${dtMonBegin}' AND time<'${dtMonEnd}' AND request LIKE '%test_flink_orders_target%' AND request <> 'SELECT COUNT(*) FROM test_flink_orders_target' ORDER BY time;
EOF

  echo
  echo "======================================================="
  echo "Comparing data in databases..."
  echo "======================================================="

${MYSQL} -v -t <<-EOF
  SELECT COUNT(*) FROM test_flink_orders;

  SELECT * FROM test_flink_orders ORDER BY orderID desc limit 10;
EOF

${VSQL} -e <<-EOF
  SELECT COUNT(*) FROM test_flink_orders_target;

  SELECT * FROM test_flink_orders_target ORDER BY orderID desc limit 10;
EOF

  exit
}


function start_mon ()
{
  dtMonBegin="$(date -Iseconds)"
  trap mon_finish SIGINT SIGTERM

  while true ; do 
    srcRowCount="$(get_source_row_count)"
    tgtRowCount="$(get_target_row_count)"
    echo "$(date +%H:%M:%S) [status] jobs = $(${FLINK_HOME}/bin/flink list -r | grep -c "${JOB_NAME}")" \
         ", rows: src = ${srcRowCount}, tgt = ${tgtRowCount}, gap = $((srcRowCount-tgtRowCount))"
    sleep 2
  done
}


function stop_mon ()
{
  scriptName="$(basename ${0})"
  if ps -ef | grep -v grep | grep -qe "${scriptName}\s*.*\s*start_mon" ; then
    ps -ef | grep -e "${scriptName}\s*.*\s*start_mon" | grep -v grep | awk '{print $2}' | xargs kill -SIGTERM
  elif ps -ef | grep -v grep | grep -qe "${scriptName}" ; then
    ps -ef | grep -e "${scriptName}" | grep -v grep | awk '{print $2}' | xargs kill -SIGTERM
  fi
}


ALLCASES=(init start_job stop_job resume_job cancel_job start_gen gen_data stop_gen start_mon stop_mon get_source_row_count get_target_row_count)


showUsage ()
{
  cat <<-EOF >&2
Usage: $(basename ${0}) [$(sed 's/ /\] \[/g'<<<"${ALLCASES[*]}")]
Options:
    -h show this usage info.
EOF
}


while getopts ":h:" opt; do
  case $opt in
    ?)
      showUsage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      showUsage
      exit 1
      ;;
  esac
done
shift $(($OPTIND -1))


if [ -z "$*" ] ; then
  cases=(init start_job "gen_data&" start_mon)
else
  cases=("$@")
fi

for caseName in "${cases[@]}" ; do
  # caseName with "&" means running asyn
  async=0
  if [ "${caseName: -1}" = "&" ] ; then
    async=1
    caseName="${caseName%?}"
  fi

  if grep -wq "${caseName}"<<<"${ALLCASES[*]}" ; then
    if [ "${async}" = "1" ] ; then
      eval "${caseName}" &
    else
      eval "${caseName}"
    fi
  else
    echo "Unkown case [${caseName}]!" >&2
    echo "" >&2
    showUsage
    exit 1
  fi
done

