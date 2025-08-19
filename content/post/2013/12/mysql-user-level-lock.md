---
title: MySQL의 User Level Lock를 활용한다면?
author: gywndi
type: post
date: 2013-12-02T02:13:40+00:00
url: 2013/12/mysql-user-level-lock
categories:
  - MariaDB
  - MySQL
tags:
  - Lock
  - MySQL

---
# Overview

DB에는 크게는 두 가지 타입의 Lock이 있습니다. Table Level Lock, Row Level Lock.. 두 가지 타입의 Lock은 RDBMS에서 대표적인 Lock이라고 지칭할 수 있습니다.

Table Level Lock은 데이터 변경 시 테이블 자체를 Lock을 걸어 안전하게 데이터를 변경하는 방식이고, Row Level Lock은 변경되는 칼럼의 Row에만 Lock을 걸어서 데이터를 조작하는 방식입니다. 일반적인 상황에서는 두 가지의 Lock만으로도 충분히 다양한 사용자의 요구사항을 충족할 수가 있습니다.

그러나, 테이블 파티셔닝을 하는 경우나, 혹은 다양한 서버에 데이터가 분산 저장되는 경우 DB 내적인 제약사항 혹은 데이터 공간 자체의 한계로 인해 상황에 따라 더욱 확장된 Lock이 필요한 경우가 있습니다.

MySQL에서는 User Level Lock 기능을 제공하는데, 오늘은 이것에 관련된 내용을 정리해보도록 합니다.

# Why User Level Lock?

User Level Lock에 대해 언급하기에 앞서서 조금 전 언급했던 파티셔닝 시 제약 사항에 대해서 간단하게 짚고 넘어가도록 하죠. ^^

MySQL에서 테이블을 파티셔닝 하게 되면, 단일 테이블로 보여지지만 내부적으로는 수 개의 테이블로 쪼개져서 별도의 테이블로 관리가 됩니다. 즉, 특정 테이블을 10개로 파티셔닝을 하였다면, DB내적으로는 10 개의 테이블을 Merge한 형태로 관리하는 모습을 보여줍니다.

![MySQL table partition files](/img/2013/11/MySQL-table-partition-files-1024x420.png)

그런데 물리적인 저장소를 분산 저장하기 위해서는 가장 중요한 제약 사항이 있는데, **파티셔닝 키 안에 Primary Key 안에 포함이 되어야 한다는 것**입니다. Primary Key가 일반적으로 물리적인 저장소의 주소 역할을 일반적으로 수행하기 때문에 당연한 현상일 수 있겠죠.

여기서, 가장 큰 제약 사항 하나!! 바로 Primary Key 외에 추가로 Unique 속성과 같은 제약 사항을 추가할 수 없다는 것입니다. Foreign Key 도 당연히 추가할 수 없습니다. 어찌 보면, 거대 테이블을 처리하기 위한 일부 기능적인 부분 포기(?)라고 볼 수도 있겠네요. ^^;;

그런 상황 속에서 User Level Lock을 잘~ 활용한다면 단순히 파티셔닝 제약 조건을 뛰어넘어 다수의 서버 환경에서도 적용할 수 있습니다.

# User Level Lock?

서론이 너무 길었네요. 이제 User Level Lock에 대해서 정리해보도록 하겠습니다.

User Level Lock이란 사용자가 특정 문자열에 Lock을 걸 수 있는 Lock을 의미합니다. 그리고 User Levl Lock 관련 메쏘드는 아래와 같습니다.

  * **GET_LOCK(str,timeout)**  
    문자열 str에 해당하는 Lock을 획득하는 메쏘드. Lock 획득 성공 시 1리턴, timeout 동안 Lock획득 못한 경우 0 리턴, 에러 발생 시 NULL 리턴
  * **IS\_FREE\_LOCK(str)**  
    문자열 str을 사용할 수 있는 상태인지 체크
  * **IS\_USED\_LOCK(str)**  
    문자열 str이 사용되고 있는 지 체크
  * **RELEASE_LOCK(str)**  
    str에 걸려있는 Lock을 해제

단, 주의할 점은 User Level Lock은 Client Base가 아닌 Server Base로 동작한다는 점입니다. 당연한 이야기이겠지만, 다수의 클라이언트에서 User Level Lock을 사용하게 되면, 클라이언트가 아닌 서버 측에서 경합이 발생한다는 점입니다. ^^

문자열에 Lock을 걸 수 있는 이 기능을 활용한다면, 앞서 말씀드린 파티셔닝 제약 혹은 물리적인 제약 사항을 극복(?)할 수 있는 솔루션이 될 수 있습니다.

# Partitioning Limitation?

테이블 파티셔닝이 반드시 필요한 상황에서 일정 기준으로 유니크 보장도 하고 싶은 경우가 있습니다. 예를 들어 1개월 간 세션 키를 발급하는 경우, 그 기간 동안에는 절대 세션 키가 중복되어서는 안됩니다. 그렇다고 모든 유저에서 발급되는 세션키를 데이터 정리 없이 매번 서버에 적재할 수도 없는 노릇이죠.

이러한 요구 사항 속에서 User Level Lock을 활용하여 제약을 극복해 봅시다.

세션 키를 발급하는 순서는 다음과 같습니다.

![](/img/2013/12/user-level-lock.png)

테이블 스키마는 아래와 같이 간단하게 정의한다고 가정했을 때,

```sql
create table t_sessions(
  user_id int not null,
  s_key varchar(32) not null,
  create_at datetime not null,
  primary key(user_id, create_at),
  key ix_skey(s_key)
) engine=innodb
partition by range columns(create_at)(
  partition p_201310 values less than ('2013-11-01'),
  partition p_201311 values less than ('2013-12-01'),
  partition p_201312 values less than ('2014-01-01')
)
```

각 단계 별로 SQL을 간단하게 작성해본다면 다음과 같습니다. 위에서 주목할 사항은 s\_key에는 유니크 속성이 없음에도 s\_key를 중복 체크를 할 수 있다는 점입니다.

```sql
##  1단계
select get_lock('session key', 1);

## 2단계
select 1 from t_sessions
where s_key = 'session key';

## 3단계 (30일 동안 중복 세션 키가 없는 경우)
insert into t_sessions values ('myid','session key',now());

## 4단계
select release_lock('session key');
```

꽤 많은 코드(?)들을 생략하기는 했지만.. 흐름만 알려드리기 위한 예시라.. 넓은 마음으로 이해해 주세요. ^^;

위 예시를 활용한다면, 파티셔닝 테이블에 Foreign Key 효과도 넣을 수 구현할 수 있겠네요. (이것은 멋진 상상력을 발휘해서 구현해보세요. ㅎ)

# Conclusion

User Level Lock은 앞에서의 간단한 파티셔닝 테이블 뿐만 아니라, 전~혀 연관이 없는 테이블 사이의 데이터를 처리하는 데에도 활용할 수 있습니다. 게다가, 동일 서버가 아닌, 다수 서버에서 분산된 데이터를 같이 처리해야하는 경우에도 유용하게 사용할 수 있습니다.

**User Level Lock은 사용자가 메쏘드를 통해 특정 문자열에 대하여 Lock을 획득하는 것**으로, MySQL 테이블 간 제약 사항을 간단하게 극복할 수 있는 초석이 될 수 있습니다. 적절한 시점에 활용하여, 데이터 신뢰성 향상은 물론 개발 시 스트레스도 줄여보도록 해요. ^^