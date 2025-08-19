---
title: SQLite 2탄 – 데이터와 인덱스 구조!!
author: gywndi
type: post
date: 2013-09-01T13:29:33+00:00
url: 2013/09/let-me-know-data-index-of-sqlite
categories:
  - SQLite
tags:
  - SQLite

---
여름은 거의 막바지로 치닫은 지금, 벌초 시즌이 찾아왔네요. 시원할줄만 알았던 산속 아침이 왜이렇게 따갑고, 오늘따라 산은 왜이렇게 가파르게 느껴지던지.. 집에 돌아오자마자, 쓰러졌습니다. ^^;

# Overview

지난 1탄에 이어 SQLite에 대해 간단하게 포스팅하려 합니다. 어떤 솔루션을 사용하든, DB를 사용함에 있어서, 논리적인 데이터 모델을 정확하게 알고 있는 것이 중요하다고 생각합니다.

SQLite 역시 Database이고, 데이터 또한 나름의 구조를 가지고 있고, 재미있는 특성이 있죠. ^^

# Data 구조

먼저 Data의 생김새를 먼저 살펴보도록 하겠습니다. SQLite의 **각각의 Row는 고유의 8Byte 정수 타입의 RowID**를 가집니다.  그리고 RowID 순서로 데이터는 저장됩니다. RowID가 생소한 분이 계실 수도 있겠네요. ^^ 특히 MySQL을 거의 사용하셨던 분에게는 낯선 용어가 될 수도 있겠죠.

RowID는 말 그대로 Row의 ID를 의미하며, DBMS마다 생김새는 다르지만, 특정한 행에 접근하기 위한 "주소"와 동일한 역할을 하는 개념이라고 생각하면 됩니다.

![SQLite Data](/img/2013/09/SQLite-Data.png)

오라클에서라면, RowID 안에는 Row가 존재하는 물리적인 정보, 즉 블록 정보와 같은 항목들이 RowID에 포함이 됩니다. 이와 반대로 MySQL의 InnoDB에서는 RowID 역할을 Primary Key가 수행합니다. PK순으로 구성된 B-트리를 통해 데이터의 위치를 찾아가는 것이죠.

그렇다면, SQLite에서의RowID특성은 어떨까요? 바로 방금 말씀드린 것대로, 8바이트의 정수 타입으로 RowID가 일단은 "내부적"으로 관리됩니다. 백문이 불여일견!! SQLite에서 다음과 같은 테이블을 생성을 하고 데이터를 넣습니다.

```sql
CREATE TABLE test(
  no integer,
  id integer
);

sqlite> INSERT INTO test VALUES (45, 1);
sqlite> INSERT INTO test VALUES (40, 2);
sqlite> INSERT INTO test VALUES (10, 3);
```

3건의 데이터를 Insert한 이후에 전체 데이터를 다음과 같이 조회해보도록 하죠.

```sql
sqlite> SELECT * FROM test;
45|1
40|2
10|3
```

두둥! 당연히 위에서 넣은 순서로 데이터를 볼 수 있습니다. 그렇다면, 여기에서 RowID를 조회해볼까요? 동일한 조건에서 아래처럼 "rowid"를 포함하여 조회 쿼리를 수행합니다.

```sql
sqlite> SELECT rowid, * FROM test;
1|45|1
2|40|2
3|10|3
```

헉!! 새로운 데이터 1,2,3이 보입니다!! 이것이 바로 SQLite에서 8Byte 정수형 데이터 RowId입니다!! 앞서 RowID가 일단은 "내부적"으로 관리된다는 말에서 눈치 빠르신 분들은 다른 무언가가 있다는 것을 아셨을 것으로 생각되는데요, 그렇습니다. SQLite에서 RowID가 반드시 내부적으로만 관리되는 것이 아닙니다.

만약 **Primary Key가  정수 타입인 경우, Primary Key가 RowID역할을 대체**합니다. 다음 예제를 보시죠.

```sql
CREATE TABLE test(
  no integer primary key,
  id integer
);

sqlite> INSERT INTO test VALUES (45, 1);
sqlite> INSERT INTO test VALUES (40, 2);
sqlite> INSERT INTO test VALUES (10, 3);
```

앞 예제랑은 no칼럼이Primary Key로 선언되었다는 것 외에는 전~혀 다른 것이 없습니다. 그리고 데이터를 45, 40, 10 순으로 넣었으니 당근 결과 또한 넣은 순서로 나와야될 것이라고 생각하겠죠?

```sql
sqlite> SELECT * FROM test;
10|3
40|2
45|1
```

그러나 예상과는 다르게, 결과값이 순서대로 출력되지 않습니다. 왜그럴까요? 이번에는 RowID를 포함하여 조회해봅시다.

```sql
sqlite> SELECT * FROM test;
10|10|3
40|40|2
45|45|1
```

Primary Key가 없는 상태에서는 분명 1부터 순차적으로 증가했던 RowID가 이번에는 Primary Key와 동일한 값으로 저장이 되어 있습니다. 데이터는 RowID 순서로 저장되기 때문에 결과적으로 넣은 순서와는 다르게 보여지는 것이죠. ^^

만약 RowID값이 어플리케이션 로직과 밀접하게 연관이 되어있다면, (제 경우 오라클에서 조금이라도 빠르게 데이터에 접근하기 위해 RowID자체를 칼럼에 포함한 적도 있습니다. ^^;;) 반드시 명시적으로 RowID가 정확하게 관리가 되어야합니다. 이 경우 "INTEGER PRIMARY KEY AUTOINCREMENT"처럼 자동 증분하는 형태로 Primary Key를 정의한다면, 현재 RowID값은 어떠한 경우에도 변경되는 일은 없겠죠. ^^

# Index 구조

인덱스 구조를 알아볼까요? 인덱스에 대한 설명은 심~플 그 자체입니다.

**Index는 인덱싱을 하는 "타겟 칼럼을 Key"로alue값으로 RowID값입니다.** RowID가 데이터가 위치하는 정보를 포함하는 키이므로, 당연한 이야기겠죠. ^^;

![SQLite Index](/img/wp-content/uploads/2013/09/SQLite-Index1.png)

너무 짧다고요? 그래서 인덱스에 대한 내용을 조~금 더 붙여봤습니다.

SQLite도 나름 실행계획이 있고, 실행계획을 바탕으로 빠르게 데이터를 접근하고자 통계 정보를 관리합니다. 통계 정보에 저장된 데이터 분포도 값을 기준으로 어떤 인덱스를 타야 가장 빠르게 데이터에 접근할 수 있는지를 "재빠르게" 결정하는 것이죠.

이것과 관련된 테이블이 바로 "sqlite\_stat1" 라는 놈입니다. 그런데 아쉽게도, 이놈은 SQLite DB파일이 만들어지면서 자동으로 생성되지는 않습니다. ㅜㅜ Analyze 이후에 생성 혹은 업데이트되는 테이블이죠. 만약, 아~무런 조작없이 SQLite DB파일을 만들고 테이블을 생성한 이후에 sqlite\_stat1 테이블을 조회하게 되면, 없는 테이블이라고 나옵니다.

간단한 예제를 준비했습니다. ^^ 아래와 같은 테이블과 인덱스를 생성한 이후에 10 건의 데이터를 넣습니다.

```sql
CREATE TABLE test(
  no integer primary key,
  id integer,
  c1 integer,
  c2 integer
);
sqlite> CREATE UNIQUE INDEX ux01 ON test(id);
sqlite> CREATE INDEX ix01 ON test(c1);
sqlite> CREATE INDEX ix02 ON test(c1, c2);

sqlite> INSERT INTO test VALUES (1, 10, 3, 4);
sqlite> INSERT INTO test VALUES (2, 11, 3, 5);
sqlite> INSERT INTO test VALUES (3, 12, 3, 6);
sqlite> INSERT INTO test VALUES (4, 13, 3, 7);
sqlite> INSERT INTO test VALUES (5, 14, 3, 8);
sqlite> INSERT INTO test VALUES (6, 15, 3, 9);
sqlite> INSERT INTO test VALUES (7, 16, 3, 10);
sqlite> INSERT INTO test VALUES (8, 17, 3, 11);
sqlite> INSERT INTO test VALUES (9, 18, 3, 12);
sqlite> INSERT INTO test VALUES (10, 19, 3, 13);
```

그리고 sqlite\_stat1 테이블을 조회해봅니다. 역시나, 없는 테이블이라고 나옵니다. (단, 이미 Analyze를 하시고, 있다고 우기시면, 저 울꺼예요!! -\_-++)

```sql
sqlite> SELECT * FROM sqlite_stat1;
Error: no such table: sqlite_stat1
```

이제 아래처럼 Analyze를 수행하고, 바로 방금 쿼리를 똑같이 질의합니다. 엇! 무언가 결과가 나옵니다.

```sql
sqlite> SELECT * FROM sqlite_stat1;
test|ix02|10 10 1
test|ix01|10 10
test|ux01|10 1
```

_"테이블명|인덱스명|데이터건수 카디널리티"_ 형태로 출력됩니다. 카디널리티(Cardinality)란 데이터 중복 건 수라고 간단하게 생각하면 되는데, Primary Key혹은 Unique Key인 경우는 당연히 1이되겠죠. 그리고 평균 카디널리티 값이 낮을수록 인덱스 효율이 좋다고 보면 됩니다. 더욱 자세한 내용은 패~스!

위에서 가장 하단의 ux01은 유니크 속성의 키입니다. 총 데이터는 10건이었고, 유니크 속성이므로 가장 뒤에는 1이 붙습니다. 효율 좋은 인덱스죠. 이와는 다르게 ix01을 보면 모두 동일한 값입니다. 이 경우 10, 최악의 효율을 자랑(?)하죠. 만약 ix02와 같이 두 개 칼럼을 붙여서 인덱스를 생성하였다면, 칼럼 순으로 카디널리티가 보여집니다. c1 혼자라면 최악의 효율이겠지만, c2와 함께라면 유니크 인덱스와 맞먹을 만큼 좋은 효율을 가집니다.

SQLite에서 쿼리가 자꾸 예상 밖으로 이상하게 실행되고 느리게만 나온다면, 한번쯤은 Analyze를 해보는 것도 좋은 생각입니다. 그러면 데이터 분포도를 참고하여 나름 최적의 실행계획으로 데이터를 추출하게 되죠. 단, Analyze는 자동으로 수행되지 않는다는 점과 모바일 환경에서는 상당한 부담이 될 수 있는 작업인만큼, 수행 시점을 "반드시" 심사숙고하여 결정하시기 바래요. ^^

# Conclusion

사실 장황하게만 늘어놨지, 오늘 공유드린 내용은 참으로 간단합니다.

  * **Data / Index는 모두 B- Tree로 관리**
  * **Data는 RowID 순으로 관리**
  * **Index는 RowID를 Value로 가짐**

예상치 못한 결과에 당황하셨다면, 한번 쯤은 데이터 및 인덱스 구조를 한번 의심해보세요. 그리고 쿼리 결과가 이상하다면, 엄한 인덱스를 타고 있는지, 데이터 분포도가 어떤지도 파악해볼만한 요소입니다.

벌초 후 피곤해서, 간단하게 적는다는게 또 주저리주저리 늘어놨군요. ^^;

이어질 다음 SQLite 시리즈 포스팅도 기대(?)해주세요.