---
title: MySQL에서 커버링 인덱스로 쿼리 성능을 높여보자!!
author: gywndi
type: post
date: 2012-04-19T15:21:20+00:00
url: 2012/04/mysql-covering-index
categories:
  - MySQL
  - Research
tags:
  - Covering Index
  - MySQL
  - Performance

---
안녕하세요.  오늘 짧지만 재미있는 내용을 하나 공유할까 합니다.

커버링 인덱스(Covering Index)라는 내용인데, 대용량 데이터 처리 시 적절하게 커버링 인덱스를 활용하여 쿼리를 작성하면 성능을 상당 부분 높일 수 있습니다.

# 커버링 인덱스란?

커버링 인덱스란 원하는 데이터를 인덱스에서만 추출할 수 있는 인덱스를 의미합니다. B-Tree 스캔만으로 원하는 데이터를 가져올 수 있으며, 칼럼을 읽기 위해 굳이 데이터 블록을 보지 않아도 됩니다.

인덱스는 행 전체 크기보다 훨씬 작으며, 인덱스 값에 따라 정렬이 되기 때문에 Sequential Read 접근할 수 있기 때문에, 커버링 인덱스를 사용하면 결과적으로 쿼리 성능을 비약적으로 올릴 수 있습니다.

백문이 불여일견! 아래 테스트를 보시죠.

# 테이블 생성

먼저 다음과 같이 테이블을 생성합니다.

```sql
create table usertest (
 userno int(11) not null auto_increment,
 userid varchar(20) not null default '',
 nickname varchar(20) not null default '',
 .. 중략 ..
 chgdate varchar(15) not null default '',
 primary key (userno),
 key chgdate (chgdate)
) engine=innodb;
```

약 1,000만 건 데이터를 무작위로 넣고 몇가지 테스트를 해봅니다.

# 커버링 인덱스(SELECT)

```sql
select chgdate , userno
from usertest
limit 100000, 100
```

```sql
************* 1. row *************
           id: 1
  select_type: SIMPLE
        table: usertest
         type: index
possible_keys: NULL
          key: CHGDATE
      key_len: 47
          ref: NULL
         rows: 9228802
        Extra: Using index
1 row in set (0.00 sec)
```

쿼리 실행 계획의 Extra 필드에 `Using Index` 결과를 볼 수 있는데, 이는 인덱스만으로 원하는 데이터 추출을 하였음을 알 수 있습니다.

이처럼 데이터 추출을 인덱스에서만 수행하는 것을 커버링 인덱스라고 합니다. 아시겠죠? ^^

그렇다면 일반 쿼리와 성능 테스트를 해볼까요?

# 커버링 인덱스(WHERE)

#### 1) 일반 쿼리

```sql
select *
from usertest
where chgdate like '2010%'
limit 100000, 100
```

쿼리 수행 속도는 30.37초이며, 쿼리 실행 계획은 다음과 같습니다.

```sql
************* 1. row *************
           id: 1
  select_type: SIMPLE
        table: usertest
         type: range
possible_keys: CHGDATE
          key: CHGDATE
      key_len: 47
          ref: NULL
         rows: 4352950
        Extra: Using where
```

Extra 항목에서 `Using where` 내용은, Range 검색 이후 데이터는 직접 데이터 필드에 접근하여 추출한 것으로 보면 됩니다.

#### 2) 커버링 인덱스 쿼리

```sql
select a.*
from (
      select userno
      from usertest
      where chgdate like '2012%'
      limit 100000, 100
) b join usertest a on b.userno = a.userno
```

쿼리 수행 시간은 0.16초이며 실행 계획은 다음과 같습니다.

```sql
************* 1. row *************
           id: 1
  select_type: PRIMARY
        table:
         type: ALL
possible_keys: NULL
          key: NULL
      key_len: NULL
          ref: NULL
         rows: 100
        Extra:
************* 2. row *************
           id: 1
  select_type: PRIMARY
        table: a
         type: eq_ref
possible_keys: PRIMARY
          key: PRIMARY
      key_len: 4
          ref: b.userno
         rows: 1
        Extra:
************* 3. row *************
           id: 2
  select_type: DERIVED
        table: usertest
         type: range
possible_keys: CHGDATE
          key: CHGDATE
      key_len: 47
          ref: NULL
         rows: 4352950
        Extra: Using where; Using index
```

Extra 에서 `Using Index`를 확인할 수 있습니다.

그렇다면 30초 넘게 수행되는 쿼리가 0.16초로 단축됐습니다. 왜 이렇게 큰 차이가 발생했을까요?

첫 번째 쿼리는 Where에서 부분 처리된 결과 셋을 Limit 구문에서 일정 범위를 추출하고, 추출된 값을 데이터 블록에 접근하여 원하는 필드를 가져오기 때문에 수행 속도가 느립니다.

두 번째 쿼리에서도 동일하게 Where에서 부분 처리된 결과 셋이 Limit 구문에서 일정 범위 추출되나, 정작 필요한 값은 테이블의 Primary Key인 userno 값입니다. InnoDB에서 모든 인덱스 Value에는 Primary Key를 값으로 가지기 때문에, 결과적으로 인덱스 접근만으로 원하는 데이터를 가져올 수 있게 됩니다. 최종적으로 조회할 데이터 추출을 위해서 데이터 블록에 접근하는 건 수는 서브 쿼리 안에 있는 결과 갯수, 즉 100건이기 때문에 첫 번째 쿼리 대비 월등하게 좋은 성능이 나온 것입니다.

# 커버링 인덱스(ORDER BY)

커버링 인덱스를 잘 사용하면 Full Scan 또한 방지할 수 있습니다. 대부분 RDBMS에는 테이블에 대한 통계 정보가 있고, 통계 정보를 활용해서 쿼리 실행을 최적화 합니다.

다음 재미있는 테스트 결과를 보여드리겠습니다. 전체 테이블에서 chgdate 역순으로 400000번째 데이터부터 10 건만 가져오는 쿼리입니다.

#### 1) 일반 쿼리

```sql
select *
from usertest
order by chgdate
limit 400000, 100
```

```sql
************* 1. row *************
           id: 1
  select_type: SIMPLE
        table: usertest
         type: ALL
possible_keys: NULL
          key: NULL
      key_len: NULL
          ref: NULL
         rows: 9228802
        Extra: Using filesort
1 row in set (0.00 sec)
```

분명 인덱스가 있음에도, Full Scan 및 File Sorting이 발생합니다. 인덱스를 태웠을 때 인덱스 블록을 읽어들이면서 발생하는 비용보다 단순 Full Scan이 더 빠르다고 통계 정보로부터 판단했기 때문이죠. 인덱스도 데이터라는 것은 항상 기억하고 있어야 합니다^^

결과 시간은 책정 불가입니다. (안끝나요~!)

#### 2) 커버링 인덱스 쿼리

위 결과와 다르게 커버링 인덱스는 조금 더 재미있는 결과를 보여줍니다.

```sql
select a.*
from (
      select userno
      from usertest
      order by chgdate
      limit 400000, 100
) b join usertest a on b.userno = a.userno
```

```sql
************* 1. row *************
           id: 1
  select_type: PRIMARY
        table:
         type: ALL
possible_keys: NULL
          key: NULL
      key_len: NULL
          ref: NULL
         rows: 100
        Extra:
************* 2. row *************
           id: 1
  select_type: PRIMARY
        table: a
         type: eq_ref
possible_keys: PRIMARY
          key: PRIMARY
      key_len: 4
          ref: b.userno
         rows: 1
        Extra:
************* 3. row *************
           id: 2
  select_type: DERIVED
        table: usertest
         type: index
possible_keys: NULL
          key: CHGDATE
      key_len: 47
          ref: NULL
         rows: 400100
        Extra: Using index
```

File Sorting이 발생하지 않고 커버링 인덱스가 사용되었으며, 실행 시간 또한 0.24초로 빠르게 나왔습니다.^^

# Conclusion

커버링 인덱스는 InnoDB와 같이 인덱스와 데이터 모두 메모리에 올라와 있는 경우에 유용하게 쓰일 수 있습니다. 물론 커버링 인덱스가 좋기는 하지만, 커버링 인덱스를 사용하기 위해 사용하지 않는 인덱스를 주구장창 만드는 것은 최대한 피해야 하겠죠^^

잊지마세요. 인덱스도 데이터라는 사실을..