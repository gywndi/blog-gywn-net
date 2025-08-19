---
title: MySQL 트랜잭션 Isolation Level로 인한 장애 사전 예방 법
author: gywndi
type: post
date: 2012-05-16T00:48:59+00:00
url: 2012/05/mysql-transaction-isolation-level
categories:
  - MySQL
tags:
  - Isolation Level
  - MySQL
  - Performance
  - 트랜잭션

---
# Overview

MySQL에서 전체 데이터를 Scan 하는 쿼리를 질의하여 서비스에 큰 영향이 발생할 수 있습니다.

InnoDB 스토리지 엔진의 기본 Isolation Level이 REPEATABLE-READ이기 때문에 발생하는 현상인데, 이것은 세션 변수 일부를 변경하여 문제를 사전에 해결할 수 있습니다.

얼마 전 이와 비슷한 장애가 발생하여 원인 분석 및 해결 방안을 포스팅합니다.

## Symptoms

Transaction Isolation Level이 REPEATABLE-READ(MySQL Default) 상태에서 Insert into Select 혹은 Create Table As Select 로 전체 테이블 참조 쿼리 실행 시 참조 테이블에 데이터 변경 작업이 대기 상태에 빠지는 현상이 있습니다.

```sql
mysql> show variables like 'tx_isolation';
+---------------+-----------------+
| Variable_name | Value           |
+---------------+-----------------+
| tx_isolation  | REPEATABLE-READ |
+---------------+-----------------+
1 row in set (0.00 sec)
```

### Insert Into Select

**세션1**

```sql
mysql> insert into activity_test_stat2
    -> select
    ->     act_type,
    ->     to_uid,
    ->     act_time,
    ->     to_user_name,
    ->     before_user_name,
    ->     count(*) cnt
    -> from activity_test
    -> group by act_type, to_uid, act_time,
    ->     to_user_name, before_user_name;
```

**세션2** 테이블에 데이터 변경

```sql
mysql> update activity_test set ACT_TYPE = 105 limit 10;
```

**세션3** update SQL는 Updating 상태

```sql
mysql> show processlist\G
************************* 1. row *************************
     Id: 255867
   User: root
   Host: localhost
     db: snsfeed
Command: Query
   Time: 1
  State: Updating
   Info: update activity_test set ACT_TYPE = 105 limit 10
************************* 2. row *************************
     Id: 255962
   User: root
   Host: localhost
     db: snsfeed
Command: Query
   Time: 2
  State: Copying to tmp table
   Info: insert into activity_test_stat2 select act_type,
```

Delete 작업 시 Update와 같이 대기 현상 또는 Dead Lock 오류 발생합니다.

```sql
mysql> delete from activity_test limit 10;
ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction
```

### Create Table As Select

**세션1**

```sql
mysql> create table activity_test_stat as
    -> select
    ->     act_type,
    ->     to_uid,
    ->     act_time,
    ->     to_user_name,
    ->     before_user_name,
    ->     count(*) cnt
    -> from activity_test
    -> group by act_type, to_uid, act_time,
    ->          to_user_name, before_user_name;
```

**세션2** 테이블에 데이터 변경

```sql
mysql> update activity_test set ACT_TYPE = 105 limit 10;
```

**세션3** update SQL는 Updating 상태

```sql
mysql> show processlist\G
************************* 1. row *************************
     Id: 255867
   User: root
   Host: localhost
     db: snsfeed
Command: Query
   Time: 2
  State: Updating
   Info: update activity_test set ACT_TYPE = 105 limit 10
************************* 2. row *************************
     Id: 255962
   User: root
   Host: localhost
     db: snsfeed
Command: Query
   Time: 4
  State: Copying to tmp table
   Info: create table activity_test_stat as select act_type,
```

Delete 작업 시 Update와 같이 대기 현상 또는 Dead Lock 오류 발생합니다.

```sql
mysql> delete from activity_test limit 10;
ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction
```

# Cause

MySQL InnoDB 스토리지 엔진의 기본 Isolation Level이 REPEATABLE-READ로 설정되어 있기 때문에 발생합니다.

REPEATABLE-READ에서는 현재 Select 버전을 보장하기 위해 Snapshot을 이용하는데, 이 경우 해당 데이터에 관해서 암묵적으로 Lock과 비슷한 효과가 나타납니다.

즉, Select 작업이 종료될 때까지 해당 데이터 변경 작업이 불가합니다.

### Transaction Isolation Level

  * **READ UNCOMMITTED**  
    다른 트랜잭션이 Commit 전 상태를 볼 수 있음  
    Binary Log가 자동으로 Row Based로 기록됨 (Statement설정 불가, Mixed 설정 시 자동 변환)
  * **READ-COMMITTED**  
    Commit된 내역을 읽을 수 있는 상태로, 트랜잭션이 다르더라도 특정 타 트랜잭션이 Commit을 수행하면 해당 데이터를 Read할 수 있음  
    Binary Log가 자동으로 Row Based로 기록됨 (Statement설정 불가, Mixed 설정 시 자동 변환)
  * **REPEATABLE READ**  
    MySQL InnoDB 스토리지 엔진의 Default Isolation Level  
    Select 시 현재 데이터 버전의 Snapshot을 만들고, 그 Snapshot으로부터 데이터를 조회  
    동일 트랜잭션 내에서 데이터 일관성을 보장하고 데이터를 다시 읽기 위해서는 트랜잭션을 다시 시작해야 함
  * **SERIALIZABLE**  
    가장 높은 Isolation Level로 트랜잭션이 완료될 때까지 SELECT 문장이 사용하는 모든 데이터에 Shared Lock이 걸림  
    다른 트랜잭션에서는 해당 영역에 관한 데이터 변경 뿐만 아니라 입력도 불가

Isolation Level에 관한 자세한 정보는 하단 MySQL 매뉴얼을 참조하세요.  
http://dev.mysql.com/doc/refman/5.5/en/set-transaction.html

## Solution

Insert into Select 경우 Isolation Level을 `READ-COMMITED`나 `READ-UNCOMMITED`로 변경하여 해결할 수 있습니다.  
다음과 같이 세션 설정을 변경 후 `Create Table As Select`, `Insert into Select`를 수행하면 문제가 없습니다.

```sql
mysql> set tx_isolation = 'READ-COMMITTED';
```

설정 파일에 영구적으로 transaction isolation 변경 적용하고자 한다면 다음과 같이 설정 후 DB를 재시작 합니다.

```sql
$ vi /etc/my.cnf
## [mysqld] 설정에 추가
transaction-isolation           = READ-COMMITTED
```

비슷한 설정으로 다음과 같이 Isolation을 변경할 수 있습니다.

```sql
mysql> SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

모든 것은 **Isolation Level이 REPEATABLE READ 이상인 경우 발생**하오니, 주의하여 사용하시기 바랍니다.

(설정 자체가 READ COMMITTED에서는 발생하지 않음)

※ 주의사항 ※  
커넥션 풀을 사용하는 경우 변경된 세션 값은 해당 커넥션이 재 시작되기 전까지 유지되므로, 반드시 사용 후 원래 설정 값으로 돌려놓아야 합니다.

# Conclusion

조금은 어려운 주제일 수 있습니다. 그러나 유독 MySQL에만 국한되는 내용이 아닌, 트랜잭션을 지원하는 DB 사용 시 반드시 알아야할 사항이라고 생각됩니다.

그러나 MySQL 에만 국한되는 내용이 아닐 뿐더러, 대용량 분석 시스템을 구상 중이라면 반드시 알아야할 사항이라고 생각합니다.^^
