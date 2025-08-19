---
title: Maria 2탄 – 진화하는 Maria, 함께하는 MySQL!!
author: gywndi
type: post
date: 2012-07-17T02:13:57+00:00
url: 2012/07/improve-mariadb-mysql
categories:
  - MariaDB
  - MySQL
tags:
  - MariaDB
  - MySQL
  - Performance

---
# Overview

MySQL 오픈 소스 진영은 더이상 단순 데이터 처리에만 강한 DBMS이기를 거부합니다. 이제는 대용량 처리에 적합하도록 탈바꿈 중입니다.

지금까지 MySQL에서는 단일 쓰레드로 Nested Loop 방식으로 쿼리를 처리하였기 때문에, 조인 건 수가 대형화될 수록 성능이 급속도로 악화되었습니다.

MariaDB는 5.3버전부터 DB 엔진과 스토리지 엔진 간의 데이터 전송이 개선되었고, 조인 시 추가적인 블록 기반의 조인 알고리즘을 제공합니다. 물론 MySQL도 5.6버전부터는 관련 기능을 어느정도 지원합니다.

변화하는 MariaDB에 대해 몇 가지 소개하도록 하겠습니다.

# Disk access optimization

### 1) Index Condition Pushdown

MySQL/MariaDB는 구조적으로 DB 엔진과 스토리지 엔진 역할이 명확하게 구분됩니다.

**DB 엔진은 데이터를 처리하여 클라이언트에게 전달하고, 스토리지 엔진은 물리적 장치에서 읽어와 DB 엔진에 전달합니다.**

이런 구조이기 때문에 다양한 스토리지 엔진을 가질 수 있다는 확장성이 있지만, 그에 따라 내부적인 비효율이 발생하기도 합니다.

다음과 같은 SQL이 호출된다고 가정합니다. tbl 테이블에는 (key\_col1, key\_col2)로 인덱스가 구성되어 있습니다.

```sql
select * from tbl
where key_col1 between 10 and 11
and key_col2 like '%foo%';
```

여기서 데이터를 스토리지 엔진에 전달할 때는 key\_col1에 해당하는 조건만 전달할 수 있습니다. key\_col2는 문자열 패턴 검색이므로 인덱스 사용에서는 무의미하기 때문이죠.

만약 key\_col1 의 between 조건 결과가 100만 건이라고 가정하면, 스토리지 엔진으로 부터 대상 데이터 100만 건을 모두 DB 엔진으로 가져와서 key\_col2 유효성을 체크합니다. 그렇기에 스토리지 엔진에서 DB엔진으로 데이터를 전송하는 &#8220;Sending Data&#8221;에서 비효율이 발생하기도 합니다.

![MariaDB None Index Condition Pushdown](/img/2012/07/MariaDB-None-Index-Condition-Pushdown.png)

그러나 MariaDB 5.3.3부터 Index Condition Pushdown 기능이 추가되면서, 인덱스 데이터 구조를 활용하여 한번 더 필터링하여 필요한 데이터만 테이블 데이터에서 읽고 DB 엔진에 전달합니다.

![MariaDB Index Condition Pushdown](/img/2012/07/MariaDB-Index-Condition-Pushdown.png)

위 그림에서는 앞선 그림과는 다르게 오직 한 건만 DB 엔진에 전달합니다. 불필요한 데이터를 DB엔진에 전달하지 않기 때문에 퍼포먼스가 크게 향상되겠죠. (간단한 테스트에서는, 1분이 넘던 쿼리가 1초 내로 처리되었습니다.^^)

단, Index Condition Pushdown 기능이 동작하기 위해서는 위와 같이 **&#8220;조건을 포함하는 형식&#8221;**으로 인덱스가 구성이 되어 있어야 합니다.

### 2) Multi-Record Read

디스크는 데이터를 읽어오는 구조 상 Random Access에 성능이 취약합니다. 데이터를 읽어들이기 위해서는 헤더를 끊임없이 움직여야 하기 때문이죠.

MariaDB에서는 효과적으로 데이터를 긁어오기 위해서 Multi-Record Read 기능을 제공합니다. 필요한 데이터를 **Rowid를 기준으로 정렬하여 디스크에 데이터를 요청**합니다. Rowid로 데이터가 정렬되었기 때문에 디스크는 Sequential하게 데이터를 읽어오죠. 즉 데이터를 읽기 위해 과도하게 헤더가 움직이지 않아도 된다는 것을 의미합니다.

Multi-Record Read를 간단하게 그림으로 표현하겠습니다.

![MariaDB Multi-Record Read](/img/2012/07/MariaDB-Multi-Record-Read.png)

인덱스 구조로부터 키가 1,2,4,6,7에 해당하는 결과를 가져와서, 이를 다시 Rowid 기준으로 정렬을 합니다.

그리고 Rowid 기준으로 실제 스토리지 엔진에 데이터를 요청하게 되는데, Rowid 순으로 접근하는 경우 디스크에서 Random Access가 최소화됩니다.

위 그림은 MyISAM 기준이며, InnoDB인 경우 Rowid 역할을 하는 Primary Key 순으로 재정렬하여 데이터를 효과적으로 가져오겠죠.^^

# Join Buffer

MariaDB 5.3부터는 조인 버퍼를 기존보다 더욱 효율적으로 사용합니다.

가변형 데이터 타입(Varchar) 경우 최대 문자열보다 부족한 부분에 \0 문자로 채우지 않고, Null 필드 경우 조인 버퍼에 적재를 하지 않고 데이터를 처리합니다. 즉 조인 버퍼 사용 효율이 증대하는 것이죠

Inner Join에서만 사용하던 조인 버퍼를 이제는 Outer Join과 Semi Join에서도 사용할 수 있도록 기능이 개선되었습니다.

### 1) Incremental Join Buffer

조인 버퍼를 더욱 더 효율적으로 사용하기 위한 새로운 접근입니다.

테이블A, 테이블B, 테이블C 등 세 개의 테이블을 조인하는 경우에는 두 개의 조인 버퍼를 내부적으로 사용합니다.

첫번째 조인 버퍼(테이블A과 테이블B 사이의 조인 버퍼)은 테이블A의 레코드 값을 임시로 저장하고 테이블B와 비교하기 위한 용도로 사용됩니다.

두번째 조인버퍼(&#8220;테이블A과 테이블B 결과&#8221;와 테이블C 사이의 조인 버퍼)는 앞선 결과 값과 테이블 C 조인을 위해 임시로 데이터를 저장하는 용도로 사용됩니다. 기존까지는 &#8220;테이블A와 테이블B 결과&#8221;를 &#8220;Copy&#8221;하면서 두번째 조인 버퍼에 적재하였습니다. 여기서 메모리에는 이중으로 데이터가 적재되는 현상이 발생하고, 비효율 현상이 발생하는 것이죠.

![MariaDB incremental join buffer](/img/2012/07/MariaDB-incremental-join-buffer.png)

그러나 Incremental join buffer 방식에서는 데이터를 복사하지 않고, 위 그림과 같이 **테이블A와 테이블B 결과가 저장된 임시 공간에 접근할 수 있는 &#8220;포인터&#8221; 값만 조인 버퍼에 저장**합니다.

즉, **&#8220;불필요한 데이터 Copy를 제거&#8221;**하면서 메모리 공간을 더욱 효율적으로 활용할 수 있는 것이죠.

### 2) Join Buffer with Outer-Join/Semi-Join

MariaDB5.3부터는 Inner-Join 뿐만 아니라 Outer-Join과 Semi-Join에서도 조인 버퍼를 활용합니다.

Outer-Join에서는 조인 버퍼 내부에 &#8220;매칭 플래그&#8221;, 즉 테이블A가 기준 테이블인 경우 관련 데이터와 매칭되는 여부를 체크하는 플래그가 내부적으로 포함됩니다.

기본적으로 매칭 플래그는 OFF 값으로 세팅되어 있고, 테이블B에서 일치하는 데이터를 찾으면 플래그를 ON으로 변경합니다.

조인 버퍼에서 테이블A와 테이블B 간 데이터 매칭 여부 수행 이후 여전히 OFF값을 플래그로 가지는 필드인 경우, 테이블B에 해당하는 칼럼들은 NULL로 채웁니다.

![MariDB Join Buffer with Outer-Join/Semi-Join](/img/2012/07/MariDB-Join-Buffer-with-Outer-Join_Semi-Join1.png)

Semi-Join(IN 안의 서브쿼리와 같은 조건)에서도 매칭 플래그가 비슷하게 사용됩니다.

다만 매칭 플래그가 On이 되는 시점에서 관련 데이터를 테이블B에서 더이상 탐색하지 않는다는 점에서 차이점이 있습니다.

# Block Based Join Algorithm

### 1) Block Nested Loop Join

블록 기반의 조인 알고리즘을 소개하기에 앞서, Block Nested Loop Join에 대해 설명하도록 하겠습니다.

테이블A와 테이블B이 있는 상태에서 다음 SQL이 호출된다고 가정합니다.

```sql
Select a.r1, b.r2
From TABEL_A a
Inner Join TABLE_B On a.r1 = b.r2
```

![MariaDB Block Nested Loop Join](/img/2012/07/MariaDB-Block-Nested-Loop-Join.png)

테이블A로부터 읽어오면서 조인버퍼가 가득 찰 때까지 채웁니다. 여기서는 연두색 사각형이 조인 버퍼를 가득 채우는 데이터라고 보면 되겠습니다.

조인 버퍼가 가득 채워지면, 테이블B를 스캔하면서 조인 버퍼에 있는 데이터와 매칭되는지 하나하나 체크하고, 매칭되면 조인 결과로 내보냅니다.

조인 버퍼 안의 모든 데이터를 비교하는 과정이 끝나면, 조인 버퍼를 비우고 다시 앞선 과정을 수행합니다. 여기서는 노란 색 사각형 부분입니다.

이러한 과정을 테이블A에서 조인 버퍼에 더이상 데이터를 채울 수 없는 시점, 즉 테이블A 조건에 해당하는 데이터를 모두 처리할 때까지 반복 수행합니다. 여기서 테이블B를 스캔하는 횟수는 조인 버퍼에 데이터가 적재되는 횟수와 동일합니다. 그리고 테이블B 데이터를 스캔할 때는 Full table scan, Full index scan, Range index scan 등으로 데이터에 접근합니다.

### 2) Block Hash Join

Block Hash Join은 MariaDB 5.3부터 제공하는 새로운 조인 알고리즘입니다.

이 알고리즘은 테이블 간 조인을 동등 비교 시에서 사용됩니다.

다른 조인 알고리즘과 마찬가지로, Block Hash Join에서도 조인 버퍼를 사용하여 테이블 간의 연관성을 체크하지만, 조인 버퍼를 사용하는 방식에서는 약간 다릅니다.

![MariaDB Block Hash Join](/img/2012/07/MariaDB-Block-Hash-Join.png)

테이블A에서 데이터를 읽어와 조인 버퍼에 밀어 넣을 때, 테이블A 조건에 해당하는 해시 값을 내부적으로 생성하고 조인 버퍼에 저장 합니다.

그리고 테이블B에서 조건을 해시값을 통하여 직접 데이터 매칭 여부를 결정하고 결과셋을 생성합니다. 즉 Nested Loop 조인 방식에서는 데이터에 순차적으로 접근해야 하는 것과는 커다란 차이가 있습니다.

조인 버퍼에 별도로 해시 값을 추가 저장하기 때문에, 기존 Block Nested Loop 방식보다는 조인 버퍼에 저장되는 데이터 양이 적으나, 테이블A가 작을수록 혹은 조인 버퍼에 저장되는 데이터 가지 수가 작을 수록 상당한 퍼포먼스를 발휘합니다.

### 3) Batched Key Access Join

기존의 Block Nested Join에서는 대용량 테이블과의 조인에서는 성능이 크게 떨어질 수밖에 없습니다.

테이블 조인 시 랜덤 Access가 발생하기 때문이죠. 그나마 인덱스를 생성하여 차선책으로 해결할 수는 있겠지만, 완벽한 대안은 아닐 것입니다.

Batched Key Access 조인은 랜덤 Access를 최대한 줄이려는 목적으로 고안된 알고리즘으로, 조인 대상이 되는 데이터를 &#8220;미리 예측&#8221;함과 동시에 디스크에 저장된 순서대로 데이터를 가져와서 &#8220;디스크 접근 효율&#8221;을 최대로 늘리자는 데 있습니다.

![MariaDB Batched Key Access Join](/img/2012/07/MariaDB-Batched-Key-Access-Join.png)

기본적인 Batched Key Access 조인은 다음과 같습니다.

다른 Block Based Join 알고리즘처럼, Batched Key Access 조인도 첫번 째 피연산자의 레코드 값을 조인 버퍼에 채웁니다.

그리고 조인 버퍼가 다시 채워지면 조인 버퍼 안에 있는 레코드와 매칭이 될 수 있는 값을 조인 테이블로부터 &#8220;미리&#8221; 찾아냅니다.

![MariaDB Batched Key Access Join](/img/2012/07/MariaDB-Batched-Key-Access-Join2.png)

조인 버퍼 안에 있는 레코드와 매칭이 될 수 있는 값을 미리 찾아내기 위해서 Multi-Record Read 인터페이스를 호출합니다.

Multi-Record Read는 조인 버퍼 안의 모든 레코드로 구성된 키 값들로 테이블B와 연관된 인덱스 룩업을 수행하고, 테이블B의 레코드를 빠르게 가져오기 위해 Rowid 순으로 데이터를 검색 합니다. 자세한 내용은 상단에 설명되어 있습니다. ^^

그리고 조인 버퍼의 레코드와 &#8220;미리 가져온&#8221; 테이블B의 데이터를 비교하여 조인 조건이 맞는지를 체크하고 최종적으로 결과값으로 출력하는 것이죠.

# Conclusion

물론 위에서 소개한 기능은 대부분 상용 DBMS에서 구현되어 있습니다. 그리고 그동안은 MySQL DB 엔진 태생적인 문제로 단순 데이터 처리 혹은 작은 데이터 조각만을 취급하는 소규모 DBMS로 인식되어 왔던 것이죠. 또한 옵티마이저 기능이 여전히 좋지 않기 때문에, 쿼리 작성 시에도 상당한 노력을 기울여야 최상의 퍼포먼스가 나옵니다.

하지만, 점차적으로 기능이 개선됨에 따라 MariaDB혹은 MySQL을 통해서도 얼마든지 어느정도의 대용량 데이터를 처리할 수 있는 모습으로 변모하고 있습니다.

더이상 DB 태생적인 한계점이 사라진다는 점에서 앞으로 MySQL 오픈소스 진영의 다음 행보가 상당히 기대됩니다.

**<참고자료>**  
* http://kb.askmonty.org/en/what-is-mariadb-53/
* http://kb.askmonty.org/en/index-condition-pushdown/  
* http://kb.askmonty.org/en/block-based-join-algorithms/#batch-key-access-join
* http://kb.askmonty.org/en/multi-range-read-optimization/
* http://assets.en.oreilly.com/1/event/2/Batched%20Key%20Access_%20a%20Significant%20Speed-up%20for%20Join%20Queries%20Presentation.ppt
