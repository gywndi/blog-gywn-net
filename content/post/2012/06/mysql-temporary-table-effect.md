---
title: MySQL에서 Temporary Table을 활용한 데이터 질의..그 효과는?
author: gywndi
type: post
date: 2012-06-15T06:15:02+00:00
url: 2012/06/mysql-temporary-table-effect
categories:
- MySQL
tags:
- Benchmark
- MySQL
- Performance

---
# Overview

오늘은 Temporary Table에 관해 포스팅을 하겠습니다. Select및 Update 등을 이따금씩 Temporary Table을 활용하여 수행하는 경우가 있습니다. 동시에 많은 데이터를 일괄 변경하는 것에서는 분명 강점이 있을 것이라 판단되는데, 어떤 상황에서 적절하게 사용하는 것이 좋을까요? 관련 성능 벤치마크 결과를 공개하겠습니다.

# **Environment**

테이블에는 약 1000만 건 데이터가 존재하며, Primary Key외에는 추가 인덱스는 생성하지 않았습니다. 서로 동등하게 빠른 데이터 접근이 가능하다는 가정 하에 PK외 인덱스에서 발생할 수 있는 성능 저하 요소를 배제하기 위해서 입니다.^^

```
## DDL for dbatest
CREATE TABLE dbatest (
i int(11) NOT NULL AUTO_INCREMENT,
c1 int(11) NOT NULL,
c2 int(11) NOT NULL,
c3 varchar(255) DEFAULT NULL,
PRIMARY KEY (i),
) ENGINE=InnoDB;

## Table Infomation
+-------------+----------+-------+-------+------------+
| TABLE_NAME  | ROWS     | DATA  | IDX   | TOTAL_SIZE |
+-------------+----------+-------+-------+------------+
| dba.dbatest | 10000105 | 1283M | 0.00M | 1283.00M   |
+-------------+----------+-------+-------+------------+
```

성능 테스트 시 Temporary Table은 아래와 패턴(tmp\_dbatest\_세션번호)으로 DB 세션 단위로 정의하여 성능을 측정하였습니다. 물론 Temporary Table이 필요한 부분에서만 사용 되겠죠.^^

Memory Storage 엔진은 테이블 Lock으로 동작하지만, 자신의 Temporary Table은 자신의 세션에서만 사용하기 때문에 동시에 여러 세션에서 읽히게 되는 그런 경우는 없다고 봐도 무관합니다.

```
## DDL for Temporary Table
CREATE TEMPORARY TABLE tmp_dbatest_12(
i int not null,
primary key(i)
) engine = memory;
```

대상 테이블에는 앞에서 언급한 것과 같이 약 1,000만 건 데이터가 들어있으며, Primary Key는 1부터 순차적으으로 정의도어 있습니다.

트래픽은 Java Thread를 여러 개 발생하여 마치 실 서비스 상태와 유사한 환경을 조성하였으며, 5개 세션(쓰레드)부터 단계적으로 200개까지 세션 수를 늘려서 초당 트랜잭션 수(TPS)를 측정하였습니다.

디스크 지연으로 인한 영향을 최소화하기 위해서 메모리는 충분히 할당하였고, 데이터 생성 후에는 DB Restart를 배제함으로써 모든 데이터를 메모리에 있다고 가정하였습니다. (테스트 시 리소스 현황을 확인하면서 Disk I/O로 인한 Bottleneck이 없음을 어느정도 확신하습니다.)

테스트는 기본적으로 하나의 트랜잭션에서 20건의 데이터 Select 또는 Update를 얼마나 효율적으로 질의할 수 있느냐에 초점을 두었습니다.

자! 이제 성능 테스트 결과를 공개합니다.

# **Benchmark Result : Select**

Temporary Table 사용 유무를 나누어서 테스트를 진행하였습니다.

### **Temporary Table**

1. Drop Temporary Table
2. Create Temporary Table
3. 1부터 10,000,000 범위 숫자 20개 무작위 추출
4. 다음과 같이 Temporary Table과 Join하여 데이터 Select

```
SELECT a.i, a.c1, a.c2
FROM dbatest a
INNER JOIN tmp_dbatest_12 b ON a.i = b.i
```

## None Temporary Table
- 1부터 10,000,000 범위 숫자 20개 무작위 추출
- 다음과 같이 IN 구문을 사용하여 Select

```
  SELECT a.i, a.c1, a.c2
FROM dbatest a
WHERE a.i in (1,2,3,4,..,17,18,19,20)
```

![Performance Test Select Result](/img/2012/06/Performance-Test-Select-None-Temporary-Table.png)

동시 접속 수가 많아질수록 Temporary Table 없이 사용하는 것이 성능이 월등히 좋았습니다.

위 케이스에서는 상당히 예상 가능한 결과로, Create/Drop/Insert/Select 등 네 가지 질의가 동일 트랜잭션에서 발생하기 때문 요인으로 볼 수 있겠죠. 하지만 만약 추후 기 저장된 데이터를 재활용한다면 상당히 다른 결과를 보여줄 수 있겠죠? (예를 들어 통계 중간 단계 혹은 자주 읽히는 데이터 임시 저장이라든가..)

IN 구문 성능이 1,000건 Select에서는 어느정도 영향이 있지 않을까라는 생각이 들어서 1,000 건 동시 데이터 질의 트래픽을 발생하여 측정하였습니다.

테스트 결과는 하단과 같으며, 여전히 Temporary Table 없이 사용하는 것이 성능이 더 좋았습니다. 앞선 결과와 차이가 크지 않은 것은 Select 쿼리 자체의 부하가 늘어났기 때문으로 파악할 수 있습니다.

![Performance Test 1000 Rows Select Result](/img/2012/06/Performance-Test-Select-None-Temporary-Table2.png)

그리고 테스트 도중  “Query End” 상태로 약 20초 대기상태에 빠지는 경우가 발생하였습니다. 아마도 내부 메모리 경합으로 인한 문제가 아닐까 추측해봅니다.

![Performance Test Wait](/img/2012/06/Performance-Test-Error.png)

# **Benchmark Result : Update**

앞선 테스트 방식과 동일하게 Update에서도 Temporary Table 사용 유무에 따라 구분하였고, 동시에 20 Row의 데이터 변경하는 것에 초점을 맞추었습니다.

### **Temporary Table**

1. Drop Temporary Table
2. Create Temporary Table
3. 1부터 10,000,000 범위 숫자 20개 무작위 추출
4. 다음과 같이 Temporary Table과 Join하여 데이터 Update

```
UPDATE dbatest a
INNER JOIN tmp_dbatest_12 b ON a.i = b.i
SET a.c1 = a.c1 +10, a.c2 = a.c2 + 10000
```

### **None Temporary Table**

1. 1부터 10,000,000 범위 숫자 20개 무작위 추출
2. PreparedStatement를 사용하여 다음과 같은 쿼리 20번 수행

```
UPDATE dbatest SET c1 = c1 +10, c2 = c2 + 10000 WHERE i = ?
```
![Performance Test Update Result](/img/2012/06/Performance-Test-Update-Result.png)

Update에서는 상당한 효과를 보입니다. Temporary Table없이 단순 건 단위로 Update 수행하는 것보다 확실히 효율이 좋습니다. 데이터 처리 시 `Permission Check` -> `Open Table` -> `Process` -> `Close Table` 등과 같이 일련의 작업이 필요한데 이러한 것을 한방 쿼리로 퉁(?) 친 결과가 아닐까 생각해 봅니다. 하지만 앞서서 발생했던 처리 지연 원인이 확실하지 않은 시점에서 Update 시 무조건 좋다고 볼 수는 없겠네요.

OLTP 환경에서 안정성 검토가 이루어져야 할 것이고, 10건 이상 동시 데이터 변경 작업에서는 성능 향상 효과를 상당히 얻을 수 있겠습니다.^^

# **Conclusion**

위 결과를 정리하자면 다음과 같습니다.

Select 시에 Temporary Table을 사용하는 것은 성능 상으로는 전혀 도움이 되지 않습니다. 빈도있는 테이블 생성/삭제, 데이터 Insert및 Join Select 등 불필요한 단계 때문이죠. 하지만 중간 결과를 저장하거나, 추후 빈도있는 재사용을 위한 목적이라면 큰 효과를 볼 수 있을 것 같습니다.

그리고 위 Update 그래프 결과를 참고할 때 10건 이상 동시 데이터 업데이트 처리 시에는 분명 효율성이 상승하는 효과는 분명히 있습니다. 서비스 로직에 따라서 동시에 수많은 데이터를 업데이트 처리하는 경우에는 큰 효과를 걷을 수 있겠습니다.

하지만, 앞서서 발생했던 처리 지연을 염두해야 하며, 가능한한 Drop 및 Create 구문을 발생하지 않고 테이블을 재사용하는 방안이 조금은 더 합리적일 것 같습니다.