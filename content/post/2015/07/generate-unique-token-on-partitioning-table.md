---
title: 파티션 제약 극복기! 유니크한 토큰 값을 만들어보자!
author: gywndi
type: post
date: 2015-07-03T14:15:42+00:00
url: 2015/07/generate-unique-token-on-partitioning-table
categories:
  - MariaDB
  - MySQL
  - Research
tags:
  - MariaDB
  - MySQL
  - partition

---
# Overview

MySQL에는 날짜 별 데이터 관리를 위해 파티셔닝이라는 좋은 기능(?)을 5.1버전부터 무료(!)로 제공합니다. 일정 시간 지난 후 불필요한 데이터는 간단하게 해당 파티셔닝을 제거하면, 굳이 DELETE 쿼리로 인한 오버헤드를 방지할 수 있죠.

그러나, 파티셔닝 적용 시, **"파티셔닝 키는 반드시 PK에 포함되어야 한다", "추가 제약조건(유니크 속성)을 부여할 수 없다"**라는 대표적인 제약 조건으로 인하여, 유니크 속성을 가지는 데이터를 파티셔닝 적용이 불가한 경우가 있는데.. 이것을 해결할 수 있는 간단한 트릭을 이 자리에서 설명하고자 합니다. ^^

# Plan to..

토큰을 생성하는 경우를 간단하게 생각해볼까요? ^^

토큰, 특히 일정 시간 이후에는 절대로 활용이 되지 않는 Access Token을 생각해본다면.. 수많은 유저들이 어떤 권한을 위해 반드시 발급받아야하는 데이터죠. 기본적으로 이 값은 중복이 발생해서도 안되고, 일정 시간이 지나버리면 폐기해도 무관한 데이터입니다.

* **반드시 유니크 속성을 보장해야한다.**
* **파티셔닝 관리가 가능해야 한다.**

간단하게 스키마를 상상해보면, 아래와 같습니다. ^^

```sql
CREATE TABLE access_tokens (
  token         char(64) NOT NULL,
  expires_at    datetime NOT NULL,
  PRIMARY KEY (token)
);

```

자.. 이제 이 엄청난 데이터를 파티셔닝을 하고 싶은데.. 흠.. 가장 간단한 방법으로는 아래처럼 PK제약 조건을 충족하기 위해 PK 속에 파티셔닝 키를 포함시켜서 테이블을 파티셔닝 하는 방법이 있습니다.

```sql
CREATE TABLE access_tokens (
  token         char(64) NOT NULL,
  expires_at    datetime NOT NULL,
  PRIMARY KEY (token, expires_at)
)
PARTITION BY RANGE COLUMN (expires_at)
(PARTITION PF_20150513 VALUES LESS THAN ('2015-05-14') ,
 PARTITION PF_20150514 VALUES LESS THAN ('2015-05-15') ,
 PARTITION PF_20150515 VALUES LESS THAN ('2015-05-16'));

```

아.. 그런데 여기서 중요한 문제가.. 반드시 유니크성을 보장해야할 Token을 스키마 레벨에서 완벽하게 보장할 수 없다는 말이죠. 즉, 정말 유니크한지 확인을 하려면 발급할 Token값이 현재 테이블에 존재여부를 사전에 조회해서 체크 해봐야 합니다. 물론, 랜덤한 Hash로 Token을 발급한다면.. 중복은 매우 희박하기는 하나.. 최악의 경우를 무시할 수는 없을테니요. ^^

# How to?

이러한 상황에서 과연 어떤 트릭(?)을 써서 파티셔닝을 하면서 유니크한 Token 발급이 가능할까요? Token 특성 상 굉장히 많은 데이터가 적재될 것이기에.. 테이블 사이즈를 고려하여 **파티셔닝을 위한 별도의 칼럼(daynum) 칼럼**을 생각해봅시다. 이 값은 smallint 타입으로 2바이트로, PK에 8바이트짜리 datetime 타입이 들어가는 것 보다는 훨씬 유리하죠. 특히나 인덱스를 추가로 만들 경우!! Token에 트릭을 가미하기 위해 기존보다 4바이트가 늘어납니다. 즉, PK는 6바이트 증가!

아래와 같이 테이블을 만들어봅시다.

```sql
CREATE TABLE access_tokens (
  token         char(68) NOT NULL,
  daynum        smallint unsigned not null,
  expires_at    datetime NOT NULL,
  PRIMARY KEY (token, daynum)
)
PARTITION BY RANGE (daynum)
(PARTITION PF_20150513 VALUES LESS THAN (134),
 PARTITION PF_20150514 VALUES LESS THAN (135),
 PARTITION PF_20150515 VALUES LESS THAN (136));
```

daynum에는 무슨 값이 들어가냐고요? to\_days(now())에서 to\_days(2014-12-31)을 뺀 값이 들어갑니다. 이렇게 함으로써 단순 2바이트 사이즈로 몇 십년 치(아마도 늙어 죽을 때까지)를 관리할 수 있는 테이블 파티셔닝 관리가 가능한 것이죠.

자, 그럼.. 데이터 처리를 위한 쿼리를 만들어볼까요? Token은 SHA2로 만든다고 가정해봅시다.

```sql
## => shar2함수 안의 스트링 값과 날짜 값만 인수로..
insert into access_tokens
  ( token, daynum, expires_at )
 values
 (
   concat(SHA2(?, 256), right(hex(TO_DAYS(?)-735963),4)),
   TO_DAYS(?)-735963,
   ?
 );

setString(1, authInfo + nanoTime)
setString(2, expires_at)
setString(3, expires_at)

ex)
insert into access_tokens
 ( token, daynum, expires_at )
values
 (
   concat(SHA2('user1', 256), right(hex(TO_DAYS('2015-05-17')-735963),4)),
   TO_DAYS('2015-05-17')-735963,
   '2015-05-17'
 );
```

복잡하쥬? 간단하게 말하자면.. **SHA2로 64바이트 키를 만들고, 가장 마지막 4글자를 날짜가 가미된 문자열을 넣자는 것<**입니다. (4글자를 맞추기 위해.. )

결국 PK는 아래와 같은 형태로 관리가 되기에, Token은 유니크 보장이 된다고 할 수 있습니다. ^^(슈퍼 울트라 캡숑 "꼼수")

* **Primary Key: (SHA2+날짜,날짜)**
* **"SHA2+날짜"는 유니크 속성 보장**

데이터를 넣었으니, 데이터를 끄집어 내는 방법도 고민해봐야겠죠? 매번 조회 시 전체 파티셔닝을 뒤지지 않기 위해서는 원하는 데이터가 위치한 곳의 적절한 파티셔닝 키도 같이 전달을 해야할텐데.. 그렇다고, 어플리케이션에서 늘 daynum을 가지고 있을 수는 없는 노릇! Token에서 날짜 정보를 추출할 수 있는 방안을 고안해야 합니다. 아래처럼..

```sql
## => 토큰 값만 쿼리에 인수로..
select * from access_tokens
where daynum = conv(trim((substr(?, 65))), 16, 10) and token = ?;
setString(1, token_string)
setString(2, token_string)

ex)
select *
from access_tokens
where daynum = conv(trim((substr('0a041b9462caa4a31bac3567e0b6e6fd9100787db2ab433d96f6d178cabfce9089', 65))), 16, 10)
and token = '0a041b9462caa4a31bac3567e0b6e6fd9100787db2ab433d96f6d178cabfce9089';
```

**Token에서 65번째 부터 4글자를 가져와서, 그 데이터를 16진수 -> 10진수로 변환하여 최종적으로 daynum을 만들어보자는 것<**입니다. 실제 호출되는 쿼리는 바로 위 예제처럼사용되겠죠. ^^

쿼리가 복잡해지기는 하나.. 나름 서버에 부담없이 데이터를 최적으로 추출할 수 있는 방안이라고 봅니다.

기존 토큰 길이가, 64->68로 길어진다는 단점이 있기는 하나.. 음.. 반드시 64글자여야 한다면, SHA2결과 값에서 마지막 4글자를 빼버리는 것도 나쁘지 않다고 생각합니다. 발급된 Token은 스키마 레벨에서 유니크를 보장하고, 날짜별로 파티셔닝도 가능하니.. 일석이조!!

# Conclusion

약간(?)의 트릭으로 파티셔닝 제약을 극복하였습니다. 유니크한 Token을 파티셔닝 관리하는.. 유니크 보장을 위해 사전 SELECT 없이도 쿼리 레벨에서 해결할 수 있는 방안이죠.

Token에 날짜가 가미된 스트링을 넣되, PK를 날짜와 같이 엮어서 Token만으로 유니크를 보장하자는 것이 목적입니다.

* **Primary Key: (SHA2+날짜,날짜) => "SHA2+날짜"는 유니크**

정말 간단한 팁같지 않은 팁이기는 하나.. 대규모 Token 관리를 계획하고 있으신 분에게는 꽤 좋은 솔루션이 될 수 있다고 생각해요. 설명장애가 있어서.. 매끄럽지 않았지만.. 의미 전달이 잘 되었기를..

다음에는 또다른 재미난 팁을 소개하도록 할께요. ^^