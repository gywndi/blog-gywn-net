---
title: MySQL InnoDB에서 데이터 1건 변경 시에도 테이블 잠금 현상이 발생할 수 있다!!
author: gywndi
type: post
date: 2012-10-06T04:36:45+00:00
url: 2012/10/mysql-transaction-isolation-level2
categories:
  - MySQL
tags:
  - Isolation Level
  - MySQL
  - Performance
  - 트랜잭션

---
# Overview

[Permanent Link to MySQL 트랜잭션 Isolation Level로 인한 장애 사전 예방 법](https://gywn.net/2012/05/mysql-transaction-isolation-level) 포스팅에서 관련 주제를 다룬 적이 있습니다. InnoDB에서 `Create Table .. As Select ..` 과 같이 사용하는 경우 테이블 잠금이 발생할 수 있는 상황과 회피할 수 있는 팁이었죠.

테이블 Full-Scan 구문이 실행 시 발생할 수 있는 문제에 관한 것입니다. 하지만 때로는 변경 대상이 1 건이라도 쿼리 타입에 따라 테이블 잠금 같은 현항이 발생할 수도 있습니다.

이번 포스팅에서는 이에 관해 정리해보도록 하겠습니다. ^^

# Symptoms

다음과 같이 `NOT IN` 과 같이 부정적인 의미의 조건 구문을 사용 시 테이블 잠금 현상이 발생할 수 있습니다. NOT IN 결과 값이 1건일지로도요..

```sql
update test set col1 = 0
where col1 not in (0, 1);
```

이 경우 Read Committed 로 트랜잭션 Isolation Level을 설정해도 인덱스 칼럼 유무에 따라 테이블 잠금 현상이 발생하기도 하죠. 물론 Repeatable Read보다는 경우의 수가 크지는 않습니다.

현재 트랜잭션 Isolation Level은 다음과 같이 확인 할 수 있습니다.

```sql
mysql> show variables like 'tx_isolation';
+---------------+-----------------+
| Variable_name | Value           |
+---------------+-----------------+
| tx_isolation  | REPEATABLE-READ |
+---------------+-----------------+
1 row in set (0.00 sec)
```

# Prepare Test

### 1) 테스트 환경 구성

```sql
## 테이블 생성
create table test(
  i int unsigned not null auto_increment,
  j int unsigned not null,
  k int unsigned not null,
  l int unsigned not null,
  primary key(i)
) engine = innodb;

## 타겟 칼럼과 관계 없는 인덱스 생성
alter table test add key(l);
```

타겟 칼럼에 인덱스를 추가하는 경우 다음과 같이 수행합니다.

```sql
## 타겟 칼럼에 인덱스 생성
alter table test add key(j);
```

### 2) 데이터 생성

빠른 데이터 생성을 위해 아래와 같이 `Insert Into .. Select..` 구문을 사용합니다.

```sql
## 데이터 1 건 생성
insert into test (j, k, l)
values
(
    crc32(rand()) mod 2,
    crc32(rand()) mod 2,
    crc32(rand()) mod 2
);

## 하단 쿼리 17건 실행
insert into test (j, k, l)
select
    crc32(rand()) mod 2,
    crc32(rand()) mod 2,
    crc32(rand()) mod 2
from test;
```

### 3) 타겟 데이터 설정

타겟 데이터와 무관한 데이터를 구분하기 위해 i 값을 10000 이상인 데이터에 한에서 랜덤하게 업데이트 수행합니다.

```sql
## 타겟 칼럼1
update test set j = 99
where i > 10000
order by rand()
limit 1000;

## 비 타겟 칼럼1 - 인덱스 없음
update test set k = 99
where i > 10000
order by rand()
limit 1000;

## 비 타겟 칼럼2 - 인덱스 있음
update test set l = 99
where i > 10000
order by rand()
limit 1000;
```

# Test Scenario

테스트는 Transaction Isolation Level(Repeatable Read, Read Committed), 인덱스 칼럼 여부, 데이터 칼럼 접근 방식(PK, Index, Full-Scan) 그리고 쿼리 타입(`in`, `not in`)을 구분하여 각각 테스트하였습니다.

원활한 테스트를 위해 모든 세션에 자동 커밋 DISABLE 설정합니다.

```sql
SET SESSION AUTOCOMMIT = 0;
```

Transaction Isolation 레벨은 테스트 상황에 맞게 다음과 같이 설정합니다.

```sql
## REPEATABLE READ 인 경우 테스트 환경
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

## READ COMMITTED 인 경우 테스트 환경
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

### 세션1

변경 대상 데이터는 i 값이 10,000보다 큰 행입니다. 하단 결과 테이블에 있는 쿼리를 질의문으로 수행한 상태에서 세션2 쿼리를 실행합니다.

### 세션2

i 값이 10,000 이하인 데이터 타겟 데이터과 관계없는 데이터를 업데이트 수행합니다.

```sql
update test set j = 1 where i = 1;
```

# Test Result

테스트 결과를 캡쳐해서 알아보기는 힘들지만, 다양한 케이스를 테스트하여 정리합니다. ^^

### 1) `NOT IN` 테스트

  * Repeatable Read : Not In  사용 시 모든 경우 Lock 발생
  * Read Committed : 인덱스(PK 포함)를 사용하여 접근 시 Lock 발생

![not in result](/img/2012/10/not-in-result1.png)

### 2) `IN` 테스트

  * Repeatable Read : 풀스캔 시 Lock 발생, 인덱스(PK포함) 접근 시 Lock 발생 안함
  * Read Committed : 풀스캔, 인덱스 스캔 모두 Lock 발생 안함

![in test result](/img/2012/10/in-test.png)

# Solutions

### 1) Transaction Isolation Level 변경 & IN 구문 사용

Transaction Isolation Level을 Read Committed로 변경하고, IN 구문을 사용하도록 합니다. Not In 사용이 반드시 필요하다면 Limit 구문을 통해 한번에 많은 데이터 변경 작업이 일어나지 않도록 유도합니다.

### 2) Select 후 결과 값으로 데이터 접근

NOT IN 구문이 필요하다면, Select 구문으로 따로 구분하고 그 결과 값으로 데이터를 다시 업데이트합니다.  MySQL의 Repeatable Read에서는 스냅샷 형태로 Select 데이터 일관성을 보장하며, 데이터 업데이트와 무관한 Select 결과 값에는 다른 세션에서 데이터 변경 작업이 가능합니다.

```sql
Statement stmt = con.createStatement();
ResultSet rs = stmt.executeQuery(
                   "select i from test where j not in (0, 1)"
               );
int i = 0;
String inStr = "";
while(rs.next()){
    inStr += ((i++) > 0 ? "," : "") + rs.getInt(1);
}
rs.close();
stmt.executeUpdate(
    "update i set j = 0 where i in (" + inStr + ")"
);
```

# Conclusion

복잡한 위의 결과를 간단하게 정리하면 다음과 같습니다.

  1. 트랜잭션 Isolation Level이 Read Committed더라도 NOT IN 과 같은 부정적인 조건 질의 시 인덱스 칼럼으로 데이터에 접근하는 상황에서는 Lock이 발생합니다.
  2. 트랜잭션 Isolation Level이 Read Committed인 상태에서 IN 구문과 같은 긍정적인 조건 질의 시에는 연관없는 데이터에는 Lock을 걸지 않습니다.
  3. 트랜잭션 Isolation Level이 Repeatable Read인 경우 NOT IN 사용 시 무조건 테이블 Lock 현상이 발생합니다.
  4. 트랜잭션 Isolation Level이 Repeatable Read인 상태에서 IN 구문을 사용하는 경우에는  인덱스 칼럼으로 접근 시에는 Lock 현상이 발생하지 않습니다.

가장 안정적으로 Lock을 피하기 위해서는 **트랜잭션 Isolation Level을 Read Committed로 설정하고, 긍적적인 조건만 주는 경우**입니다.

물론 인덱스가 있는 상황이라면, 부정적인 조건 사용 시에도 데이터 접근이 빠르므로, 변경 대상 데이터가 많거나 트랜잭션이 오래 유지되지 않는 한 큰 문제는 없습니다. ^^

단, Read Committed로 변경 시 **Binary Log 포멧이 자동으로 ROW 형태로 변경되기 때문에, Binary Log 파일이 급격하게 늘어날 수 있는 경우**가 발생할 수 있으니, 내부 검토가 반드시 필요합니다.

사용할수록 나날이 새로운 사실이 발견되는 MySQL이네요.

감사합니다.