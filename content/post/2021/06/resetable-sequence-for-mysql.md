---
title: MySQL에서 리셋되는 시퀀스 만들어보기
author: gywndi
type: post
date: 2021-06-21T06:24:06+00:00
url: 2021/06/resetable-sequence-for-mysql
categories:
  - MariaDB
  - MySQL
tags:
  - MySQL
  - sequence

---
# Overview

서비스를 준비하다보면, 시퀀스에 대한 요구사항은 언제나 생기기 마련입니다. 물론, MySQL에는 기본적으로 테이블 단위로 auto_increment가 있기는 합니다만, 일반적인 시퀀스가 요구되는 환경을 흡족하게 맞추기는 어려운 실정입니다.  
보통은 Peter Zaitsev가 하단에 게시한 블로그 내용처럼, Function 기반으로 채번 함수를 만들고는 하지요. (물론 InnoDB로 지정하는 것이, 복제 상황에서는 아주 안정성을 확보하기는 합니다.)  
https://www.percona.com/blog/2008/04/02/stored-function-to-generate-sequences/

이 내용을 기반으로, &#8220;재미난 시퀀스를 만들어볼 수 없을까?&#8221; 라는 퀘스천에 따라, 이번 블로깅에서는 특정 시점에 리셋이 되는 시퀀스를 한번 만들어보고자 합니다.

# Schema

첫번째로는 현재 시퀀스를 담을 테이블 그릇(?)을 아래와 같이 생성을 해보도록 하겠습니다.

```sql
CREATE TABLE `t_sequence` (
  `name` varchar(100) NOT NULL,
  `seq_num` bigint(20) NOT NULL DEFAULT '0',
  `mtime` timestamp(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`name`)
) ENGINE=InnoDB
```

여기에서 seq_num이 매번 +1되면서 데이터를 전달해주게 되겠죠.  
Peter의 블로그와는 다르게, 저는 아래와 같이 `insert into .. on duplicate key update ..` 구문으로 Upsert 처리하여 시퀀스를 발급하도록 하겠습니다.

```sql
insert into t_sequence (name, seq_num, mtime) values ('abc', last_insert_id(1), now(6))
    on duplicate key update seq_num = last_insert_id(seq_num+1), mtime = now(6);
```

그런데, 이 구문은 단순히 시퀀스값을 매번 1씩 증가하는 것으로. 우리에게 필요한 것은 매일 0시 혹은 매시 시퀀스 값이 1부터 다시 초기화되는 로직이 쿼리안에 필요한 것입니다. 그래서, 위 쿼리를 아래와 같이 변경을 해봅니다. (매분 1로 초기화)

```sql
insert into t_sequence (name, seq_num, mtime) values ('abc', last_insert_id(1), now(6))
    on duplicate key update seq_num = last_insert_id(if(mtime &lt; date_format(now(6), '%Y-%m-%d %H:%i:00'), 1, seq_num+1)), mtime = now(6);
```

`on duplicate key update` 안에 시간을 체크하는 로직을 추가하여, 결과적으로 0분때마다 다시 1부터 다시 시작하는 값이 추출되는 것이죠.

```sql
mysql> insert into t_sequence (name, seq_num, mtime) values ('abc', last_insert_id(1), now(6))
    ->     on duplicate key update seq_num = last_insert_id(if(mtime &lt; date_format(now(6), '%Y-%m-%d %H:%i:00'), 1, seq_num+1)), mtime = now(6);
Query OK, 2 rows affected (0.00 sec)

mysql> select now(), last_insert_id();
+---------------------+------------------+
| now()               | last_insert_id() |
+---------------------+------------------+
| 2021-06-21 12:31:58 |                6 |
+---------------------+------------------+
1 row in set (0.00 sec)

mysql> insert into t_sequence (name, seq_num, mtime) values ('abc', last_insert_id(1), now(6))
    ->     on duplicate key update seq_num = last_insert_id(if(mtime &lt; date_format(now(6), '%Y-%m-%d %H:%i:00'), 1, seq_num+1)), mtime = now(6);
Query OK, 2 rows affected (0.00 sec)

mysql> select now(), last_insert_id();
+---------------------+------------------+
| now()               | last_insert_id() |
+---------------------+------------------+
| 2021-06-21 12:32:01 |                1 |
+---------------------+------------------+
1 row in set (0.00 sec)
```

자 이제, 이 쿼리들을 조합해서, 아래와 같은 Function을 만들어보겠습니다.

```sql
delimiter //
drop function nextval//
create function nextval(in_name varchar(100), in_type char(1)) returns bigint
begin
  declare date_format varchar(20);
  SET date_format = (
    case
      when in_type = 'M' then '%Y-%m-01 00:00:00'
      when in_type = 'D' then '%Y-%m-%d 00:00:00'
      when in_type = 'H' then '%Y-%m-%d %H:00:00'
      when in_type = 'I' then '%Y-%m-%d %H:%i:00'
      when in_type = 'S' then '%Y-%m-%d %H:%i:%S'
      else '%Y-%m-%d 00:00:00'
    end
  );
  insert into t_sequence (name, seq_num, mtime) values (in_name, last_insert_id(1), now(6))
      on duplicate key update seq_num = last_insert_id(if(mtime &lt; date_format(now(6), date_format), 1, seq_num+1)), mtime = now(6);
  return last_insert_id();
end
//
delimiter ;
```

Function 함수에 나와있듯이, M인경우는 매월 리셋, D는 매일 리셋, H는 매시 리셋.. 등등 파라메터로 리셋할 시점을 정해서 만들어볼 수 있겠습니다.

```sql
mysql> select nextval('abc', 'I') seq, now();
+------+---------------------+
| seq  | now()               |
+------+---------------------+
|    1 | 2021-06-21 12:40:42 |
+------+---------------------+
1 row in set (0.00 sec)

mysql> select nextval('abc', 'I') seq, now();
+------+---------------------+
| seq  | now()               |
+------+---------------------+
|    2 | 2021-06-21 12:40:52 |
+------+---------------------+
1 row in set (0.00 sec)

mysql> select nextval('abc', 'I') seq, now();
+------+---------------------+
| seq  | now()               |
+------+---------------------+
|    3 | 2021-06-21 12:40:56 |
+------+---------------------+
1 row in set (0.00 sec)

mysql> select nextval('abc', 'I') seq, now();
+------+---------------------+
| seq  | now()               |
+------+---------------------+
|    1 | 2021-06-21 12:41:00 |
+------+---------------------+
1 row in set (0.00 sec)
```

필요하다면, Function의 `insert into .. on duplicate update..` 구문 안에 더 다양한 요구 사항을 넣어볼 수 있을 듯 합니다. 🙂

# Performance

함수로 만들어지기 때문에.. 느릴 수도 있다고 선입견을 가지신 분들을 위해서.. 간단하게 아래와 같이 테스트를 해보았습니다.

### Environments

```
Intel(R) Core(TM) i3-8100 CPU @ 3.60GHz(4core), 32G Memory
```

### MySQL parameter

```sql
mysql> show variables where Variable_name in ('innodb_flush_log_at_trx_commit', 'sync_binlog');
+--------------------------------+-------+
| Variable_name                  | Value |
+--------------------------------+-------+
| innodb_flush_log_at_trx_commit | 0     |
| sync_binlog                    | 0     |
+--------------------------------+-------+
2 rows in set (0.00 sec)
```

### 1. Local test

시퀀스 특성 상 특정 row에 대한 Lock이 매번 발생할 수밖에 없습니다. 이 얘기는, 네트워크 레이턴시가 관여할 수록 더욱 낮은 퍼포먼스를 보인다는 이야기인데요. 우선 서버에 접속해서 mysqlslap으로 아래와 같이 시퀀스 발급 트래픽을 무작위로 줘봅니다.

```bash
$ time mysqlslap -utest      \
  --password=test123         \
  --create-schema=test       \
  --iterations=1             \
  --number-of-queries=100000 \
  --query="select test.nextval('abc', 'H');"
Benchmark
    Average number of seconds to run all queries: 5.979 seconds
    Minimum number of seconds to run all queries: 5.979 seconds
    Maximum number of seconds to run all queries: 5.979 seconds
    Number of clients running queries: 10
    Average number of queries per client: 10000
real    0m5.996s
user    0m0.915s
sys 0m1.709s
mysqlslap -uroot --concurrency=10 --create-schema=test --iterations=1    0.18s user 0.32s system 15% cpu 3.285 total
```

5.996초 수행되었고, 초당 16,666 시퀀스 발급이 이루어졌네요!!

### 2. Remote test

거실에 있는 블로그 서버로의 네트워크 레이턴시는 대략 아래와 같습니다. 04~0.5ms 사이를 왔다갔다 하는듯..

```bash
$ ping 10.5.5.11
PING 10.5.5.11 (10.5.5.11): 56 data bytes
64 bytes from 10.5.5.11: icmp_seq=0 ttl=64 time=0.404 ms
```

이 환경에서 위와 동일한 테스트 트래픽을 발생시켜보았습니다.

```bash
$ time mysqlslap -utest      \
  --password=test123         \
  --host=10.5.5.11           \
  --concurrency=10           \
  --create-schema=test       \
  --iterations=1             \
  --number-of-queries=100000 \
  --query="select test.nextval('abc', 'H');"
mysqlslap: [Warning] Using a password on the command line interface can be insecure.
Benchmark
    Average number of seconds to run all queries: 7.191 seconds
    Minimum number of seconds to run all queries: 7.191 seconds
    Maximum number of seconds to run all queries: 7.191 seconds
    Number of clients running queries: 10
    Average number of queries per client: 10000
mysqlslap -utest --password=test123 --host=10.5.5.11 --concurrency=10      0.43s user 0.44s system 11% cpu 7.238 total
```

7.191초 수행하였고, 초당 13,906건 정도 시퀀스 발급이 이루어졌습니다.

개인적인 생각으로는.. 단일 시퀀스 성능으로는 이정도도 나쁘지 않다고 생각합니다만.. ^^ 만약 시퀀스 자체가 이렇게 공유하는 개념이 아닌 개인별로 할당되는 구조로 관리된다면..? row lock으로 인한 불필요한 대기를 어느정도 줄여줄 수 있을 것으로 생각되네요.

```bash
$ time mysqlslap -utest      \
  --password=test123         \
  --host=10.5.5.11           \
  --concurrency=10           \
  --create-schema=test       \
  --iterations=1             \
  --number-of-queries=100000 \
  --query="select test.nextval(concat('ab',floor(rand()*10)), 'H');"
mysqlslap: [Warning] Using a password on the command line interface can be insecure.
Benchmark
    Average number of seconds to run all queries: 5.702 seconds
    Minimum number of seconds to run all queries: 5.702 seconds
    Maximum number of seconds to run all queries: 5.702 seconds
    Number of clients running queries: 10
    Average number of queries per client: 10000
mysqlslap -utest --password=test123 --host=10.5.5.11 --concurrency=10      0.40s user 0.45s system 14% cpu 5.767 total
```

앞서 7.2초 걸리던 결과를 5.7초 정도로 처리하였는데. 만약 네트워크 레이턴시가 많이 안좋은 환경에서는 Lock으로 인한 대기를 크게 경감시킴으로써 훨씬 더 좋은 효과를 보여줄 것이라 생각합니다.

# Concluion

MySQL에 없는 시퀀스를 서비스 요구사항에 맞게 좀더 재미나게 만들어보자라는 생각으로 시작하였습니다.  
특정 서비스건, 개인화 서비스건.. 0시 기준으로 새롭게 1부터 시작해야하는 시퀀스 요구사항을 가끔 듣기는 했습니다. 이럴때 기존이라면, 락을 걸고, 현재 시퀀스 값을 가지고 리셋 처리 여부를 결정해야할 것인데.. 여기서는 이것을 간단하게 단건의 INSERT 구문으로 해결을 하였습니다.

필요에 따라.. 특정 이벤트의 개인화 테이블에.. 최근 1시간동안 10회 이상이면 다시 1부터 시작하는 이상스러운 시퀀스도 재미나게 만들어볼 수 있을 듯 하네요.

오랜만의 포스팅을 마칩니다.