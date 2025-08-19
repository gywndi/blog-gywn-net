---
title: MySQL InnoDB의 메모리 캐시 서버로 변신! – 설정편 –
author: gywndi
type: post
date: 2019-09-15T11:50:15+00:00
url: 2019/09/mysql-innodb-as-cache-server-config
categories:
  - MariaDB
  - MySQL
tags:
  - memcached
  - MySQL

---
# Overview

꽤나 오래전의 일이었습니다. MariaDB에서 Handler Socket이 들어간 이후 얼마 후인 것으로 기억합니다. **MySQL lab버전에 memcached plugin 기능이 추가**되었고, **memcache protocal로 InnoDB 데이터에 직접 접근**할 수 있는 길이 열린 것이었죠. (아마도 거의 8년 정도 전의 일이었던 것같은..) 아무튼 당시, 이것에 대해 간단하게 테스트만 해보고, MySQL을 캐시형태로 잘 활용할 수 있겠다라는 희망만 품고 지나버렸다는 기억이 나네요.

이제 Disk는 과거의 통돌이 디스크가 아니죠. 기계 장치를 탈피하여, 이제는 모터없는 전자기기.. **SSD의 시대가 도래**하였습니다. 통돌이 대비, 어마어마한 수치의 Random I/O를 제공해주는만큼, 이제 DB 데이터에 새로운 패러다임(?)으로 접근할 수 있겠다는 시점이 온 것 같아요.

말이 거창했습니다. 8년이 훌쩍 지난 지금 **MySQL 5.7에서 InnoDB memcached plugin 활용성 테스트**를 해보았어요.

# MySQL memcached plugin?

MySQL 5.6부터 들어왔던 것 같은데.. **InnoDB의 데이터를 memcached 프로토콜을 통해서 접근할 수 있다는 것**을 의미합니다. 플러그인을 통하여 구동되기 때문에.. 캐시와 디비의 몸통은 하나이며, InnoDB 데이터에 직접 접근할 수 있기도 하지만, 캐시 공간을 별도로 두어.. 캐시처럼 사용할 수도 있어요. (옵션을 주면, set 오퍼레이션이 binlog에 남는다고 하던데.. 해보지는 않음 ㅋㅋ)

![innodb memcached](/img/2019/08/innodb_memcached.jpg)
출처: https://dev.mysql.com/doc/refman/8.0/en/innodb-memcached-intro.html

그런데, 만약.. 데이터베이스의 테이블 데이터를.. memcached 프로토콜로 직접적으로 access할 수 있다면 어떨까요? 메모리 위주로 데이터 처리가 이루어질 때.. 가장 많은 리소스를 차지하는 부분은 바로 **쿼리 파싱과 옵티마이징 단계**입니다. 만약 **PK 조회 위주의 서비스이며.. 이것들이 자주 변하지 않는 데이터**.. 이를테면 “서비스토큰”이라든지, “사용자정보” 같은 타입이라면..?

* PK 조회 위주의 서비스
* 변경 빈도가 굉장히 낮음

심지어 이 데이터는 이미 InnoDB 라는 안정적인 데이터베이스 파일로 존재하기 때문에.. 예기치 않은 정전이 발생했을지라도, 사라지지 않습니다. 물론, 파일의 데이터를 메모리로 올리는 웜업 시간이 어느정도 소요될테지만.. 최근의 DB의 스토리지들이 SSD 기반으로 많이들 구성되어가는 추세에서, 웜업 시간이 큰 문제는 될 것 같지는 않네요.

MySQL InnoDB memcached plugin을 여러 방식으로 설정하여 사용할 수 있겠지만, 오늘 이야기할 내용은, memcache 프로토콜만 사용할 뿐, 실제 액세스하는 영역은 DB 데이터 그 자체임을 우선 밝히고 다음으로 넘어가도록 하겠습니다.

# Configuration

오라클 문서([innodb-memcached-setup][1])를 참고할 수도 있겠습니다만, 오늘 이 자리에서는 memcached 플러그인을 단순히 memcache 프로토콜을 쓰기 위한 용도 기준으로만 구성해보도록 하겠습니다.

우선, InnoDB 플러그인 구성을 위해 아래와 같이 memcached 관련된 스키마를 구성합니다. 🙂 여기서 $MYSQL_HOME는 MySQL이 설치된 홈디렉토리를 의미하며, 각자 시스템 구성 환경에 따라 다르겠죠.

```bash
$ mysql -uroot < $MYSQL_HOME/share/innodb_memcached_config.sql
```

자, 이제 간단한 성능 테스트를 위한 환경을 구성해볼까요? 먼저 아래와 같이 테스트 테이블 하나를 생성하고, 성능 테스트를 위한 약 100만 건의 데이터를 생성해봅니다.

```
## 테이블 생성
mysql> CREATE DATABASE `memcache_test`;
mysql> CREATE TABLE `memcache_test`.`token` (
    ->  `id` varchar(32) NOT NULL,
    ->  `token` varchar(128) NOT NULL,
    ->  PRIMARY KEY (`id`)
    ->);

## 테스트 데이터 생성
mysql> insert ignore into token
    -> select md5(rand()), concat(uuid(), md5(rand())) from dual;
mysql> insert ignore into token
    -> select md5(rand()), concat(uuid(), md5(rand())) from token;
... 반복 ...

mysql> select count(*) from token;
+----------+
| count(*) |
+----------+
|   950435 |
+----------+
```

이제, 위에서 생성한 테이블을 memcached plugin이 보도록 설정 정보를 수정을 하고, 최종적으로 플러그인을 올려줍니다.

```
## 캐시 정책 변경(get만 가능하고, 캐시 영역없이 InnoDB에서 직접 읽도록 세팅)
mysql> update cache_policies set
    ->   get_policy = 'innodb_only',
    ->   set_policy = 'disabled',
    ->   delete_policy='disabled',
    ->   flush_policy = 'disabled';

## 기존 정책 삭제 후, token 신규 정책 추가
mysql> delete from containers;
mysql> insert into containers values ('token', 'memcache_test', 'token', 'id', 'token', 0,0,0, 'PRIMARY');

## InnoDB memcached 플러그인 구동
mysql> INSTALL PLUGIN daemon_memcached soname "libmemcached.so"; 
```

이 과정을 거치면, 디비 데이터를 memcached protocol로 직접 접근할 수 있는 환경이 만들어집니다. 기본 포트로 11211 포트가 개방되며, 이 포트를 통해 memcache protocal 로 get 오퍼레이션을 수행하면 InnoDB 데이터 영역으로부터 직접 데이터를 가져올 수 있습니다. (물론, 다수의 칼럼이 있는 경우)

즉, SQL 변경한 데이터를 직접 읽을 수 있다는 것이죠. (테이블 칼럼을 구분자로 맵핑하여 memcache의 VALUE를 만들 수 있으나, 여기서는 스킵합니다.)

# Performance

간단한 테스트를 해보았습니다. **SQL vs memcached!!** 생성한 데이터 전체 ID값 기준으로 랜덤한 아래 패턴의 쿼리를 각각 초당 약 7만 건의 쿼리를 수행하여 시스템 리소스를 측정하였습니다.

```
## SQL ##
SELECT * FROM token WHERE id = ${id}

## Memcache ##
get @@token.${id}
```

SQL과 memcache 모두 7만 쿼리 처리는 큰 무리없이 처리 하지만, 시스템 리소스 측면에서는 큰 차이를 보였습니다. **SQL인 경우 30~40% 리소스를 사용**하는 반면에, **memcache에서는 대략 5% 내외의 리소스를 사용**할 뿐 아주 여유있는 시스템 상황을 보입니다. SQL 파싱와 옵티마이징 단계를 스킵한, 단순 데이터 GET 처리 효과이겠죠.

![SQL vs memcache](/img/2019/09/sql_vs_memcache_result.png)

이왕 할 테스트, 장기적으로 약 10일간 초당 약 6\~7만 건 쿼리를 지속적으로 주면서 안정성 테스트를 해보았습니다.  
일단, 이 기간동안 **memcache GET 오퍼레이션 에러 카운트는 0건**입니다. 초단위 평균 응답속도 결과는 **초당 평균 0.3ms~0.5ms 사이로 좋은 응답 속도**를 보였습니다. 무엇보다, **제일 느렸던 것은 대략 1.5ms 정도**로.. DB datafile의 B-Tree로 직접 데이터를 읽을지라도, 캐시로써 전혀 손색없는 속도를 보였습니다. 🙂

```
+-----+----------+
| ms  | seconds  |
+-----+----------+
| 0.2 |       99 |
| 0.3 |   661736 |
| 0.4 |   162582 |
| 0.5 |     5686 |
| 0.6 |     1769 |
| 0.7 |     1004 |
| 0.8 |      576 |
| 0.9 |      310 |
| 1.0 |      159 |
| 1.1 |       77 |
| 1.2 |       29 |
| 1.3 |       12 |
| 1.4 |        4 |
| 1.5 |        1 |
+-----+----------+
```

# Conclusion

MySQL InnoDB에 데이터가 변경이 되면, 이를 memcached protocol로 접근할 수 있기 때문에.. 이것을 잘 활용하면 복잡한 캐시 관리 없이 쉽게 캐시 레이어 구성이 가능해보입니다.

  * 세션 혹은 토큰 데이터(사용자 데이터)를 **MySQL복제 구성**하고, 이것으로 실시간 서비스를 한다면?
  * Binlog를 통한 리플리케이터를 하나 작성해서, 원하는 형태로 **데이터를 조작(ex, json)**한 이후, 이것을 memcache protocal로 데이터를 접근한다면?
  * 코드 혹은 공통 정보에 대한 데이터(거의 안변하는 데이터)를 **캐시 구성 없이 GET 오퍼레이션으로 바로 서비스에 사용**한다면??

서비스의 요구 사항에 맞게, 데이터를 원하는 모습으로, 적재적소에 MySQL InnoDB memcached plugin을 잘 활용할 수 있다면, 휘발성에서 오는 한계점, 동기화 이슈 등등 많은 부분을 정말 단순한 구조로 해결할 수 있을 것으로 기대됩니다.

다음 편은, 이렇게 구성한 memcached plugin을 어떻게 PMM(prometheus & grafana) 구조로 쉽게 모니터링을 할 수 있을지에 대해 이야기를 해보도록 할께요.