---
title: MySQL Table Lock에 관한 이해
author: gywndi
type: post
date: 2012-01-30T06:01:51+00:00
url: 2012/01/mysql-table-lock
categories:
  - MySQL
tags:
  - Lock
  - MyISAM
  - MySQL

---
# Overview

Table Lock 스토리지 엔진 사용 시 반드시 알아야할 사항을 정리 드리겠습니다.

근래에는 물론 InnoDB가 아~주 많이 사용되고 있겠지만, 여전히 서비스에서는 MyISAM이 쓰이고 있습니다. MyISAM은 MySQL의 대표적인 스토리지 엔진이면서 내부적으로는 Table Lock으로 동작합니다.

관련 스토리지 엔진에 관한 설명은 MySQL특성을 정리한 [반드시 알아야할 MySQL 특징 세 가지](/2011/12/mysql-three-features/) 포스팅을  참고하시면, 간단한 비교를 하실 수 있습니다. 자 그럼 Table Lock 스토리지 엔진 사용 시 반드시 알아야할 사항을 정리 드리겠습니다.

# Table Lock 이해

MySQL에서 Table Lock은 다음 기준에 의해서 부여됩니다.

**Write Lock**  
> 아무런 Lock이 없으면, 해당 테이블에 Write Lock을 걸어서 데이터 읽기 또는 변경 작업을 수행하지 못하게 합니다. 만약 Read 혹은 Write Lock이 존재하면 Write Lock 큐에 Lock을 넣어서 해당 Lock이 풀릴 때까지 대기합니다.
> 
**Read Lock**  
> 아무런 Write Lock이 없으면, Read Lock을 걸어서, 데이터 변경 작업을 수행하지 못하도록 합니다. 만약 Write Lock이 있으면 Read Lock 큐에 Lock을 넣고 데이터 변경 작업이 종료될 때까지 대기합니다.
> 
> 기본적으로 Write Lock이 Read Lock보다 우선 순위가 높지만,  
> 다음과 같이 LOW_PRIORITY 로 변경 가능합니다.  
> Example)  
> mysql> INSERT INTO **LOW_PRIORITY** table_name&#8230;  
> mysql> DELETE **LOW_PRIORITY** FROM table_name&#8230;  
> mysql> UPDATE **LOW_PRIORITY** table_name SET&#8230;
> 
> 참고) [Internal Locking Methods](http://dev.mysql.com/doc/refman/5.1/en/internal-locking.html)

위를 다시 간단하게 정리하자면, Write Lock 상태에서는 다른 세션이 해당 테이블 접근이 불가한 상태이고, Read Lock 상태는 다른 세션이 데이터를 Read까지만 가능하다고 볼 수 있습니다.

그러나! 만약에 Write 또는 Read 수행이 오래 걸리는 경우는 어떨까요? Read Lock은 다른 Read 세션에 영향을 미치지 않을 것으로 보이지만, 때로는 Dead Lock을 유발하는 요소가 될 수도 있습니다.

# Example

다음과 같은 경우를 예를 들어보겠습니다. 테이블은 MyISAM 엔진입니다.

**Session 1**

```sql
## 수행 시간이 오래 걸리는 조회 쿼리 발생
mysql> SELECT * FROM tab01 WHERE  sleep(1000);
```

이 경우 다른 세션에서도 tab01 테이블에서 얼마든지 데이터 조회가 가능합니다.

**Session 2**

```sql
## Read Lock 상태 테이블에 데이터 변경
mysql> UPDATE tab01 SET c1 = '' WHERE i = 4;
```

Update 쿼리는 Session1의 Select 쿼리가 종료될 때까지 대기합니다.

**Session 3**

```sql
## Read Lock 상태이고, Write Lock이 대기 상태에서 Select 수행
mysql> SELECT * FROM tab01 LIMIT 10;
```

Session 2 의 Write Lock에 의해 Read 불가한 상태로 빠집니다.

프로세스 현황을 확인해보면 아래와 같습니다.  
![Table Lock Process List](/img/2012/01/Table_Lock_Process_List.png)

정상적이라면 Select 수행되는 동안 다른 세션에서도 Select가 수행되어야 하는데, 쿼리 우선 순위에 의해서 Select 세션이 Lock 상태로 빠진 것을 확인할 수 있습니다.

# Conclusion

MySQL Replication 사용 시 Slave 서버에서 Dead Lock은 위와 같은 상황에서 얼마든지 발생할 수 있기 때문에, 반드시 알고 있어야 합니다. (통계성 SQL이 실행되는 테이블에 Update 발생 시 다른 세션에서는 해당 테이블 데이터 조회 불가)

MyISAM 스토리지 엔진이 트랜잭션이 많은 경우 부적합한 가장 큰 이유입니다.^^