---
title: MySQL Heatwave를 살펴보았습니다
author: gywndi
type: post
date: 2022-05-23T00:00:00+00:00
url: 2022/05/mysql-heatwave
categories:
  - Cloud
  - MySQL
tags:
  - HeatWave
  - MySQL

---
# Overview

안녕하세요. 너무 오랜만에 글을 올려봅니다. 올해도 벌써 반이 훌쩍지나버렸네요. 

MySQL을 쓰시는 분들, 아니 **RDBMS를 써오시던 분들의 가장 가려운 부분은 개인적으로 통계 쿼리 수행 속도**라고 봅니다. 특히나 데이터 사이즈가 하루가 다르게 폭발적으로 증가해가는 상황에서 너무나도 반가운 소식이라고 봅니다. HTAP(Hybrid transactional/analytical processing) 구현이라 하는데.. 

오늘 이 포스팅에서는 서비스 활용 관점으로 Heatwave를 이야기해보도록 하겠습니다.

# MySQL Heatwave는?

Oracle Cloud에서 제공하는 OLAP 분산 클러스터로, MySQL의 InnoDB데이터를 자동으로 Heatwave 클러스터로 동기화하여, 제공하는 스토리지 엔진 플러그인입니다. 
![Content is described in the surrounding text](https://dev.mysql.com/doc/heatwave/en/images/hw-ml-genai-architecture.png)

그림을 보면. 결국 HeatWave는 HeatWave Cluster와 HeatWave storage engine 두 가지로 분류해볼 수 있겠네요. 마치. MySQL ndb cluster와 같이. 🙂

* **HeatWave storage engine** 
  - 스토리지 엔진(SECONDARY 엔진)으로, MySQL서버와 HeatWave Cluster간 데이터의 통신 역할
  - 사용자의 쿼리가 실행되는 이것을 Heatwave쪽으로 Query pushdown 하여 쿼리를 실행
* **HeatWave Cluster** 
  - 데이터를 저장 및 프로세싱하는 분산 노드의 집합.
  - Oracle cloud 내부에 구성된 HeatWave Storage 레이어에 데이터에 저장.
  - InnoDB 데이터와 다른 저장소에 저장이 됨.

MySQL을 통해 들어온 쿼리를 HeatWave Storage 엔진을 통해 HeatWave Cluster에 Query pushdown하여 전달하여 분산 컴퓨팅을 한 후 쿼리 결과를 사용자에게 다시 제공을 해주는?? **기본적으로 모든 데이터 변경은 InnoDB Only라는 측면**에서는 다른듯 하네요. 구조상으로는 ndb cluster와 유사한것 같은데.. 트랜잭션 상으로는 미묘하게 다른 느낌이 오네요. <figure class="wp-block-image size-large">

![](/2022/05/image-1024x549.png")

MySQL InnoDB 스토리지 엔진과 직접적으로 연계하여 데이터를 처리해볼 수 있는 분석 용도의 **분산 Column-Oriented Database** 이라고 봐도 무관해보이네요. 

# Using HeatWave 

거창하게 별도의 테이블을 만들어서 진행한다기 보다는.. 아래와 같이 ALTER 구문을 통해서 설정을 해볼 수 있다 하네요.

```sql
## 64KB 넘는 컬럼 제외
mysql> ALTER TABLE orders MODIFY description BLOB NOT SECONDARY;

## SECONDARY_ENGINE 엔진 지정
mysql> ALTER TABLE orders SECONDARY_ENGINE = RAPID;

## 데이터 복사(InnoDB->Heatwave)
mysql> ALTER TABLE orders SECONDARY_LOAD;
```

이 일련의 과정을 거치면, 이후부터는 **서비스에서 사용하는 InnoDB변경 내역이 백그라운드에서 자연스럽게 Heatwave 데이터노드로 동기화** 될 것이고, 이 내용을 기반으로 바로 OLAP쿼리를 수행해볼 수 있습니다. 만약 Heatwave에서 지원하는 쿼리만 사용한다고 했을 시에.. 사용자는 분석을 위해 별도의 데이터소스를 통하지 않고도, MySQL 데이터 소스 하나만으로도 원하는 결과를 깔끔(?)하게 도출해볼 수 있겠습니다.

```sql
## secondary 사용할래~ (Heatwave 사용할래)
SET SESSION use_secondary_engine=ON;

## secondary 사용할래~ (InnoDB에서 데이터 처리할래)
SET SESSION use_secondary_engine=OFF;
```

HeatWave에서 데이터를 제거하고 싶으면, 아래와 같이 SECONDARY_UNLOAD를 실행하면 됩니다. 

깔끔하게 테이블도 그냥 InnoDB로만 변경하고자 한다면, 아래와 같이 SECONDARY_ENGINE을 NULL로 지정해야 합니다. 만약 **Truncate 혹은 DDL작업이 필요하다면. 반드시 SECONDARY_ENGINE을 NULL로 변경**해야 작업 수행할 수 있습니다.

```sql
## HeatWave Cluster에서 데이터 제거
mysql> ALTER TABLE orders SECONDARY_UNLOAD;

## SECONDARY_ENGINE 사용 비활성화
mysql> ALTER TABLE orders SECONDARY_ENGINE = NULL;
```

# Workload Optimization

Heatwave에서는 데이터를 저장하는 방식(Encoding)과 인덱싱(Placement Key)을 하는 두가지 방법으로 워크로드에 맞는 설정을 해볼 수 있습니다. **기본적으로 모든 옵션은 각 칼럼들의 COMMENT내용을 활용**하고 있으며. 대소문자를 구분하기에, 반드시 모두 대문자로 명시를 해야한다고 하네요. ex) `COMMENT 'RAPID_COLUMN=ENCODING=VARLEN'`

## 1. Encoding

Variable-length Encoding, Dictionary encoding 두가지 타입을 제공하며. 각각 다른 특성을 가집니다.

### 1.1. Variable-length Encoding

기본 인코딩 타입으로, NULL을 허용하며, 문자열 컬럼 저장에 효율적이라고 합니다. 

MySQL에서 제공해주는 캐릭터셋을 지원하며, 무엇보다 데이터 처리 시 MySQL의 메모리가 크게 필요치 않기 때문에 자원 활용이 좋다고 하네요. `Group by`, `Join`, `Limit`, `Order by` 등을 지원합니다.

```sql
ALTER TABLE orders
  MODIFY `O_COMMENT` VARCHAR(79) COLLATE utf8mb4_bin NOT NULL
  COMMENT 'RAPID_COLUMN=ENCODING=VARLEN';
```

### 1.2. Dictionary encoding (SORTED)

데이터 가짓수(Distinct)가 적은 스트링 저장에 효율적이라 합니다. 

예를 들면.. `코드`와 같은? 메모리 사용을 MySQL 엔진 쪽을 활용하기 때문에. 관련 리소스 소모가 있을 수 있다고 하고.. 특성만 보면. B-map 인덱싱과 왠지 유사한 느낌적인 느낌도.. ^^ 

`Join`, `Like` 등을 비롯한 문자열 연관 오퍼레이션에 제약이 있다고 합니다. 마찬가지로, 컬럼 레벨로 아래와 같이 코멘트에 인코딩 옵션을 넣어서 설정해볼 수 있겠습니다.

```sql
ALTER TABLE orders
  MODIFY `O_COMMENT` VARCHAR(79) COLLATE utf8mb4_bin NOT NULL
  COMMENT 'RAPID_COLUMN=ENCODING=SORTED';
```

## 2. Data Placement Keys

기본적으로 PK 기반으로 데이터가 분산되어 관리되지만.. 성능 또는 기타 목적을 위해 별도로 생성하는 키라고 되어있고. 마치 여러개의 Clustering Key를 설정하는 듯한 개념으로 보이네요. Variable-length 인코딩만 지원합니다.테이블당 1~16까지 지정할 수 있으며. 하나의 숫자는 하나의 컬럼에만 할당 가능합니다. (복합 인덱싱 불가!)

```sql
ALTER TABLE orders
  MODIFY date DATE COMMENT 'RAPID_COLUMN=DATA_PLACEMENT_KEY=1',
  MODIFY price FLOAT COMMENT 'RAPID_COLUMN=DATA_PLACEMENT_KEY=2';
```

지금까지 나름 메뉴얼 기반으로 HeatWave에 대해서 퀵하게 훑어보았습니다. 그러나, 역시 직접 해보는 것이 특성을 알아볼 수 있는 제대로된 접근이기에. 개인적으로 의문나는 부분 위주로 몇가지 테스트해보았습니다.

# Setup HeatWave

앞에서 이야기를 한 것처럼, HeatWave는 Oracle Cloud에서만 사용할 수 있습니다. 테스트를 위해, 일단 가입을 하고 무료 테스트 코인을 받아서 아래와 같이 HeatWave 용도의 데이터베이스를 생성해봅니다.

![](/img/2022/05/image-2-1024x614.png)

생성을 완료했을지라도, 정작 해당 스토리지 엔진이 존재하지 않는데. 아직 HeatWave 클러스터를 생성하지 않았기 때문이죠. 

```sql
mysql> show engines;
+--------------------+---------+--------------+------+------------+
| Engine             | Support | Transactions | XA   | Savepoints |
+--------------------+---------+--------------+------+------------+
| FEDERATED          | NO      | NULL         | NULL | NULL       |
| MEMORY             | YES     | NO           | NO   | NO         |
| InnoDB             | DEFAULT | YES          | YES  | YES        |
| PERFORMANCE_SCHEMA | YES     | NO           | NO   | NO         |
| MyISAM             | YES     | NO           | NO   | NO         |
| MRG_MYISAM         | YES     | NO           | NO   | NO         |
| BLACKHOLE          | YES     | NO           | NO   | NO         |
| CSV                | YES     | NO           | NO   | NO         |
| ARCHIVE            | YES     | NO           | NO   | NO         |
+--------------------+---------+--------------+------+------------+
```

MySQL 인스턴스를 누르고, Heatwave
![](/img/2022/05/image-3-1024x202.png)

MySQL에 접속을 해서 엔진을 확인해보면, 아래와 같이 RAPID 엔진이 정상적으로 올라와 있네요.

```sql
mysql> show engines;
+--------------------+---------+--------------+------+------------+
| Engine             | Support | Transactions | XA   | Savepoints |
+--------------------+---------+--------------+------+------------+
| FEDERATED          | NO      | NULL         | NULL | NULL       |
| MEMORY             | YES     | NO           | NO   | NO         |
| InnoDB             | DEFAULT | YES          | YES  | YES        |
| PERFORMANCE_SCHEMA | YES     | NO           | NO   | NO         |
| RAPID              | YES     | NO           | NO   | NO         | <<==  올라옴
| MyISAM             | YES     | NO           | NO   | NO         |
| MRG_MYISAM         | YES     | NO           | NO   | NO         |
| BLACKHOLE          | YES     | NO           | NO   | NO         |
| CSV                | YES     | NO           | NO   | NO         |
| ARCHIVE            | YES     | NO           | NO   | NO         |
+--------------------+---------+--------------+------+------------+
```

# Loading Test Data

Oracle 메뉴얼에 [Airport 샘플 데이터](https://dev.mysql.com/doc/heatwave/en/mys-hw-airportdb-quickstart.html#mys-hw-airportdb-install-compute)를 공개해놓았기 때문에. 이것을 적극 활용해봐야겠죠? 큰 테이블 만들기도 참 귀찮았는대.. 아. 일단. 이 전에. MySQL에 붙기 위한.. Compution instance를 하나 생성부터 해야겠군요. 이 부분은 스킵!

MySQL클라이언트를 설치하고, 추가로 데이터 로딩에서 mysql shell을 쓰기에 같이 설치!

```bash
[opc@instance-20220516-1013 ~]$ sudo yum install mysql
[opc@instance-20220516-1013 ~]$ sudo yum install mysql-shell
```

정상적으로 MySQL에 쿼리를 실행할 수 있는 환경이 구성되었다면, 이제 테스트 데이터를 받아서, mysql shell로 데이터를 로딩해보도록 하겠습니다.

```bash
[opc@instance-20220516-1013 ~]$ wget https://downloads.mysql.com/docs/airport-db.tar.gz
[opc@instance-20220516-1013 ~]$ tar xzvf airport-db.tar.gz
[opc@instance-20220516-1013 ~]$ cd airport-db
[opc@instance-20220516-1013 airport-db]$ mysqlsh chan@10.0.0.143
Please provide the password for 'chan@10.0.0.143':

MySQL 10.0.0.143:3306 ssl JS > util.loadDump("airport-db", {threads: 16, deferTableIndexes: "all", ignoreVersion: true})
```

데이터 로딩이 마무리되었고.. HeatWave를 테스트해볼 환경이 모두 준비 되었습니다.

```sql
mysql> show tables from airportdb;
+---------------------+
| Tables_in_airportdb |
+---------------------+
| airline             |
| airplane            |
| airplane_type       |
| airport             |
| airport_geo         |
| airport_reachable   |
| booking             |
| employee            |
| flight              |
| flight_log          |
| flightschedule      |
| passenger           |
| passengerdetails    |
| weatherdata         |
+---------------------+
```

# Heatwave VS InnoDB

문서에 나온대로, 실제 성능을 체감해보도록 하겠습니다. 

## 1. Initialize HeatWave

쿼리를 날리기에 앞서. airportdb에 있는 모든 테이블을 Heatwave로 변경을 시켜줘야겠죠? 이 과정이 생각보다 오래 걸리지 않더군요. (일부 테이블은 몇천만건 데이터를 가지고 있음에도..)

```sql
mysql> call sys.heatwave_load(json_array('airportdb'), null);
mysql> select name, load_status
    -> from performance_schema.rpd_tables,
    ->      performance_schema.rpd_table_id
    -> where rpd_tables.id = rpd_table_id.id;
+-----------------------------+-----------------------+
| NAME                        | LOAD_STATUS           |
+-----------------------------+-----------------------+
| airportdb.flight_log        | AVAIL_RPDGSTABSTATE   |
| airportdb.airport_geo       | AVAIL_RPDGSTABSTATE   |
| airportdb.flight            | AVAIL_RPDGSTABSTATE   |
| airportdb.passengerdetails  | AVAIL_RPDGSTABSTATE   |
| airportdb.passenger         | AVAIL_RPDGSTABSTATE   |
| airportdb.airplane          | AVAIL_RPDGSTABSTATE   |
| airportdb.weatherdata       | LOADING_RPDGSTABSTATE |
| airportdb.flightschedule    | AVAIL_RPDGSTABSTATE   |
| airportdb.booking           | AVAIL_RPDGSTABSTATE   |
| airportdb.employee          | AVAIL_RPDGSTABSTATE   |
| airportdb.airplane_type     | AVAIL_RPDGSTABSTATE   |
| airportdb.airport           | AVAIL_RPDGSTABSTATE   |
| airportdb.airline           | AVAIL_RPDGSTABSTATE   |
| airportdb.airport_reachable | AVAIL_RPDGSTABSTATE   |
+-----------------------------+-----------------------+

mysql> select count(*) from booking;
+----------+
| count(*) |
+----------+
| 54304619 |
+----------+
```

## 2. Query HeatWave

실행계획을 보면, 별다른 옵션없이 옵티마이저가 이 쿼리를 RAPID엔진을 사용하는 것으로 Extra부분에서 정보를 확인해볼 수 있겠습니다. 그런데 실제 가격별 카운팅 결과는 0.09초에 마무리가 되는.. 굉장히 좋은 성능을 보여주네요.

```sql
mysql> SET SESSION use_secondary_engine=ON;
mysql> explain
    -> SELECT booking.price, count(*)
    ->   FROM booking WHERE booking.price > 500
    ->  GROUP BY booking.price
    ->  ORDER BY booking.price LIMIT 10;
+----+----------+----------+--------------------------------------+
| id | rows     | filtered | Extra                                |
+----+----------+----------+--------------------------------------+
|  1 | 54202876 |    33.33 | Using ..Using secondary engine RAPID |
+----+----------+----------+--------------------------------------+

mysql> SELECT booking.price, count(*)
    ->   FROM booking WHERE booking.price > 500
    ->  GROUP BY booking.price
    ->  ORDER BY booking.price LIMIT 10;
+--------+----------+
| price  | count(*) |
+--------+----------+
| 500.01 |      860 |
| 500.02 |     1207 |
| 500.03 |     1135 |
| 500.04 |     1010 |
| 500.05 |     1016 |
| 500.06 |     1039 |
| 500.07 |     1002 |
| 500.08 |     1095 |
| 500.09 |     1117 |
| 500.10 |     1106 |
+--------+----------+
10 rows in set (0.09 sec)
```

## 3. Query InnoDB

InnoDB로만 데이터를 처리했을 시 결과입니다. 실행계획을 보면, 앞에서 명시되었던 RAPID 엔진 사용이 사라졌고. 실제 카운팅 쿼리를 수행해보면. 10초 이상.. 무려 1000배의 시간이 더 걸리는 성능을 보이죠. 일단, 이런 효율면에서는 확연하게 성능차가 나오네요.

```sql
mysql> SET SESSION use_secondary_engine=OFF;
mysql> explain
    -> SELECT booking.price, count(*)
    ->   FROM booking WHERE booking.price > 500
    ->  GROUP BY booking.price
    ->  ORDER BY booking.price LIMIT 10;
+----+----------+----------+--------------------------------------+
| id | rows     | filtered | Extra                                |
+----+----------+----------+--------------------------------------+
|  1 | 54202876 |    33.33 | Using where; Using..; Using filesort |
+----+----------+----------+--------------------------------------+
mysql> SELECT booking.price, count(*)
    ->   FROM booking WHERE booking.price > 500
    ->  GROUP BY booking.price
    ->  ORDER BY booking.price LIMIT 10;
+--------+----------+
| price  | count(*) |
+--------+----------+
| 500.01 |      860 |
| 500.02 |     1207 |
| 500.03 |     1135 |
| 500.04 |     1010 |
| 500.05 |     1016 |
| 500.06 |     1039 |
| 500.07 |     1002 |
| 500.08 |     1095 |
| 500.09 |     1117 |
| 500.10 |     1106 |
+--------+----------+
10 rows in set (10.66 sec)
```

이것 외에도 다른 다양한 쿼리가 몇몇 샘플로 더 공개되어 있지만, 이것은. 스킵하는 것으로..

# Operational Test

아무리 엔진이 좋아도, 운영 측면에서 준비가 안되어있다면, 이것은 빛좋은 개살구일뿐입니다. 만약 서비스에서 사용을 한다면, 좋을만한 포인트가 무엇일지 기준으로 추가로 테스트해보았습니다.

## 1. Online DDL

아쉽게도 Heatwave로, 아니 `SECONDARY_ENGINE=RAPID` 으로 정의된 테이블에는 `ALTER`구문이 동작하지 않습니다. 만약, 테이블 구조 변경이 필요하다면. `SECONDARY_ENGINE`속성을 없앤 후에 `ALTER`를 수행해야합니다,

```sql
mysql> alter table heatwave_test add c10 varchar(10);
ERROR 3890 (HY000): DDLs on a table with a secondary engine defined are not allowed.

mysql> truncate table heatwave_test;
ERROR 3890 (HY000): DDLs on a table with a secondary engine defined are not allowed.

mysql> alter table partition_test secondary_engine = null;

mysql> truncate table heatwave_test;
Query OK, 0 rows affected (0.01 sec)
```

테이블 칼럼 추가 삭제 시에는 이런 부담을 안고 가야하기에. DDL이 절대 변하지 않을만한 상황에서 활용을 하는 것이 좋을 듯 하네요.

## 2. Partitioning

앞선 이야기에서처럼. `SECONDARY_ENGINE=RAPID` 으로 정의된 테이블에는 ALTER구문이 동작하지 않습니다. 이것은 파티셔닝 추가/삭제에 대해서도 마찬가지입니다. 

사실 테이블에서는 디비에 부담없이 오래된 데이터를 정리하는 목적으로 파티셔닝을 많이 활용하기 때문에.. 아쉬운점이 많네요. 특히나. 이 테이블은 아무래도 분석 관련된 쿼리가 많이 활용될 것이라, 데이터도 많아지게 될 것이고. 아주 오래된 데이터를 효율적으로 제거하는 방안도 있어야할텐데..

무엇보다, 파티셔닝 테이블로 로딩을 했을지라도. RAPID 내부적으로는 의미가 없기도 하고요. 사실. Heatwave쪽에 별도의 데이터가 존재하기에. 당연한 결과이기는 합니다만..

```sql
mysql> SET SESSION use_secondary_engine=OFF;
+----+---------------------------------+---------+-------------+
| id | partitions                      | rows    | Extra       |
+----+---------------------------------+---------+-------------+
|  1 | p2017,p2018,p2019,p2020,p999999 | 9533500 | Using where |
+----+---------------------------------+---------+-------------+

mysql> SET SESSION use_secondary_engine=ON;
+----+------------+---------+---------------------------------------+
| id | partitions | rows    | Extra                                 |
+----+------------+---------+---------------------------------------+
|  1 | NULL       | 9533500 | Using .. Using secondary engine RAPID |
+----+------------+---------+---------------------------------------+
```

파티셔닝이 안되는 것은 아니지만, 우선 파티셔닝을 했을지라도 파티셔닝 구조변경을 위해서는 HeatWave재구성을 해야한다는 측면에서는 매리트가 없습니다. 이럴꺼면 그냥 테이블 단위 파티셔닝을 개발 레벨에서 구현을 해서 사용하는 것이 훨씬 유리해보이네요.

그냥 파티셔닝은 비효율적이다라는 정도로 정리!

# Performance TEST

사실 Cloud에서 동작을 하는 것이라. 성능적으로 기하 급수적으로 변화시킬만한 파라메터가 없는 것은 사실입니다. 그러나, 적어도 Heatwave 테이블과 InnoDB로만 구성된 테이블간의 성능차이는 확인해봐야겠죠?

```sql
mysql> create database bmt;
mysql> use bmt;

mysql> create table tb_innodb_only(
    ->  i int not null primary key auto_increment,
    ->  c1 varchar(100) not null,
    ->  c2 varchar(100) not null,
    ->  c3 varchar(100) not null,
    ->  c4 varchar(100) not null,
    ->  c5 varchar(100) not null,
    ->  c6 varchar(100) not null,
    ->  c7 varchar(100) not null,
    ->  ts timestamp
    -> );

mysql> create table tb_innodb_rapid(
    ->  i int not null primary key auto_increment,
    ->  c1 varchar(100) not null,
    ->  c2 varchar(100) not null,
    ->  c3 varchar(100) not null,
    ->  c4 varchar(100) not null,
    ->  c5 varchar(100) not null,
    ->  c6 varchar(100) not null,
    ->  c7 varchar(100) not null,
    ->  ts timestamp
    -> );
mysql> alter table tb_innodb_rapid secondary_engine=rapid;
mysql> alter table tb_innodb_rapid secondary_load;
```

## 1. InnoDB VS HeatWave

InnoDB와 HeatWave 양쪽으로 두 벌의 데이터가 존재하기 때문에. SELECT와 같이 둘중 하나 담당하는 쿼리 테스트는 의미없을 듯 하고. 양쪽 모두 영향을 미치는 데이터 변경으로 테스트를 해보겠습니다. 테스트 트래픽은 쉽게쉽게 mysqlslap 유틸을 활용하여 생성해보도록 하겠습니다.

### 1.1 InnoDB performance

10건 데이터를 100개 프로세스가 나눠서 넣는 것으로. 총 10번 수행합니다.

```bash
mysqlslap                     \
  -u chan -p -h 10.0.0.143    \
  --concurrency=100           \
  --iterations=10             \
  --number-of-queries=100000  \
  --create-schema=bmt         \
  --no-drop                   \
  --query="insert into tb_innodb_only values (null, uuid(), uuid(), uuid(), uuid(), uuid(), uuid(), uuid(),now());"

Benchmark
  Average number of seconds to run all queries: 20.136 seconds
  Minimum number of seconds to run all queries: 18.896 seconds
  Maximum number of seconds to run all queries: 20.851 seconds
  Number of clients running queries: 100
  Average number of queries per client: 1000
```

유입 쿼리량을 보니.. 대략 초당 6,000 정도 쿼리를 처리하네요.

```plain
|Com_insert|5804|
|Com_insert|5430|
|Com_insert|6218|
|Com_insert|5759|
|Com_insert|6173|
|Com_insert|5823|
|Com_insert|5586|
|Com_insert|5460|
|Com_insert|6085|
|Com_insert|5842|
|Com_insert|6312|
|Com_insert|5807|
|Com_insert|6210|
|Com_insert|6036|
```

### 1.2 HeatWave Performance

이번에는 동일한 트래픽을 Heatwave로 구성된 테이블에 줘보도록 하겠습니다. 마찬가지로, 10건 데이터를 100개 프로세스가 나눠서 넣습니다.

```bash
mysqlslap                     \
  -u chan -p -h 10.0.0.143    \
  --concurrency=100           \
  --iterations=10             \
  --number-of-queries=100000  \
  --create-schema=bmt         \
  --no-drop                   \
  --query="insert into tb_innodb_rapid values (null, uuid(), uuid(), uuid(), uuid(), uuid(), uuid(), uuid(),now());"

Benchmark
  Average number of seconds to run all queries: 20.271 seconds
  Minimum number of seconds to run all queries: 19.184 seconds
  Maximum number of seconds to run all queries: 21.355 seconds
  Number of clients running queries: 100
  Average number of queries per client: 1000
```

유입 쿼리량을 보니.. 대략 초당 6,000 정도 쿼리를 처리하네요. 차이가 거의 없다고 해야하나.. -\_-;

```sql
|Com_insert|5925|
|Com_insert|6201|
|Com_insert|5621|
|Com_insert|5923|
|Com_insert|5837|
|Com_insert|5609|
|Com_insert|5926|
|Com_insert|5268|
|Com_insert|5977|
|Com_insert|5630|
|Com_insert|6185|
|Com_insert|5046|
|Com_insert|6335|
|Com_insert|5761|
|Com_insert|6222|
|Com_insert|5926|
```

## 2. Count query for paging

생각없이 검색 쿼리를 날려보았는데. 의외의 결과가 나와서 추가로 적어봅니다.

서비스에서 많이 사용하는 쿼리 중 제일 컨트롤이 어려운 부분은 사실 페이징입니다. 데이터가 폭발적으로 증가할수록 언제나 늘 고민을 해야하는 것도. 바로 게시판 타입의 서비스이기도 하죠. 물론 오프셋 기반의 페이징(특정 ID값 이전의 10건씩 가져오는 방식)은 소셜 서비스의 방대한 데이터를 처리하기 위해 많이들 사용하는 추세이기는 합니다만.. 모든 요구사항을 이런식으로 구현하기에도 명백히 한계가 있습니다.

그런데. Heatwave를 태우게 되면. 단순 카운팅 뿐만 아니라. 아래와 같이 별도의 검색조건을 추가로 준다고 할지라도. 큰 무리없이 데이터 카운팅 결과를 가져옵니다. (0.05초 VS 10.84초)

```sql
#####################################
# Heatwave
#####################################
mysql> SET SESSION use_secondary_engine=ON;
Query OK, 0 rows affected (0.00 sec)

mysql> SELECT count(*)
    ->   FROM booking
    ->  WHERE booking.price > 500
    ->    AND seat like '24%';
+----------+
| count(*) |
+----------+
|     1407 |
+----------+
1 row in set (0.05 sec)

#####################################
# Without heatwave
#####################################
mysql> SET SESSION use_secondary_engine=OFF;
Query OK, 0 rows affected (0.00 sec)

mysql> SELECT count(*)
    ->   FROM booking
    ->  WHERE booking.price > 500
    ->    AND seat like '24%';
+----------+
| count(*) |
+----------+
|     1407 |
+----------+
1 row in set (10.84 sec)
```

의외로. 제 개인적으로는 워드프레스와 상당히 궁합이 맞을 수 있겠다는 생각이?? 새로운 발견!!

# Conclusion

지금까지 몇가지를 추가로 살펴본 HeatWave는.. 이렇게 정리를 해보고싶네요.

* Oracle Cloud에서만 사용 가능
* InnoDB 데이터와 **별개의 분산 스토리지에 저장**된다. (InnoDB first)
* **Online DDL은 불가**하고. **DDL시에도 secondary_engine을 비활성** 필요
* InnoDB는 파티셔닝 구성해도, HeatWave는 내부적으로 파티셔닝 구성 안되어 있음.<br />파티셔닝의 관리 역시 순탄치 않음
* **InnoDB와 성능 차이(INSERT)가 없음. **
* 게시판 카운팅 쿼리에 나름 적합(?)

무엇보다 Oracle cloud에서만 사용할 수 있다는 점이 아쉽기는 하지만. 

OnPremise로 가능할지라도. Heatwave 클러스터 구축 및 관리가 필요할 것이니. 이것이 꼭 단점으로만 부각할만한 것은 아니라고 봅니다. 그리고. **Oracle cloud에서는 의외로.. MySQL binlog가 활성화**되어있고, **Replication 계정을 추가**할 수 있기에.. 데이터 핸들링 측면에서는 꽤나 좋은 환경이라는 생각도 문득 드네요. ㅎㅎ (DBaaS인데 이 점은 정말 매력적인 포인트입니다. 데이터의 흐름을 가두지 않는 것. 아 근데 나중에 막힐라나?? -\_-;;)

이런 측면을 놓고보면, 안정성/성능을 좀더 파악해봐하겠지만 ㅎㅎ

긴 글 읽으시느라 고생많았습니다. 오랜만에 포스팅을 마치겠습니다.