---
title: MySQL 성능 죽이는 잘못된 쿼리 습관
author: gywndi
type: post
date: 2012-05-11T06:12:07+00:00
url: 2012/05/mysql-bad-sql-type
tags:
  - MySQL
  - Performance
  - SQL
  - Tuning

---
# Overview

안정적인 서비스 유지를 위해서는 쿼리 작성이 상당히 중요합니다. 잘못된 쿼리 하나가 전체적인 퍼포먼스를 크게 저해하기도 하고 최악의 경우 장애 상황까지 치닫기 때문이죠

단일 코어에서 Nested Loop Join으로 데이터를 처리하는 MySQL 특성 상 쿼리 구문에 큰 영향을 받습니다. ([반드시 알아야할 MySQL 특징 세 가지](/2011/12/mysql-three-features/) 참고)

그래서 오늘은 쿼리 작성 시 기피해야 하는 사항 세 가지정도 골라봅니다.

# Case 1

```sql
SELECT @RNUM:=@RNUM+1 AS RNUM, ROW.*
FROM (SELECT @RNUM:=0) R,
(
    SELECT
        M.MASTER_NO,
        M.TITLE,
        MI.PATH,
        M.REGDATE,
        CM.TYPE
    FROM MAIN AS M
    LEFT OUTER JOIN TAB01 AS MI
        ON M.MASTER_NO = MI.MASTER_NO
    INNER JOIN TAB02      AS CM
        ON M.MASTER_NO = CM.MASTER_NO
    WHERE M.DEL_YN = 'N'
    ORDER BY M.MASTER_NO DESC
) ROW
LIMIT 10000, 10
```

![SQL Plan Case1-1](/img/2012/05/SQL_Plan_Case1-1.png)

오라클 쿼리에 익숙하신 분들이 흔히 하는 실수입니다.

오라클 rownum 효과를 내기 위해 (SELECT @RNUM:=0) 로 번호를 붙이다 보니 결과적으로 필요없는 데이터를 스캔합니다. Nest Loop Join으로 데이터를 처리하기 때문에 퍼포먼스가 상당히 떨어집니다.

Row 번호는 어플리케이션 서버에서 생성하고, 다음과 같이 쿼리를 작성하는 것이 좋습니다.

```sql
SELECT
    M.MASTER_NO,
    M.TITLE,
    MI.PATH,
    M.REGDATE,
    CM.TYPE
FROM MAIN AS M
LEFT OUTER JOIN TAB01 AS MI ON M.MASTER_NO = MI.MASTER_NO
INNER JOIN TAB02      AS CM ON M.MASTER_NO = CM.MASTER_NO
WHERE M.DEL_YN = 'N'
ORDER BY M.MASTER_NO DESC
LIMIT 10000, 10
```
![SQL Plan Case1-2](/img/2012/05/SQL_Plan_Case1-2.png)

변환 전/후 쿼리 프로파일링을 해보면 다음과 같습니다. 변환 후에 필요없는 데이터 스캔에 소요되던 Sending Data가 사라지고, 단순하게 처리됩니다.

![SQL Profile Case1](/img/2012/05/SQL_Profile_Case1.png)

# Case 2

Where 조건 Left Value에 함수 적용하여 결과적으로 Full Scan이 발생하는 경우입니다. 서비스 구현 단계에서는 쉽고 직관적으로 보일지는 몰라도, DB 내부 데이터 처리에서 엄청난 자원을 소모합니다.

이런 습관은 DBMS 상관없이 기피해야 합니다.

```sql
SELECT *
FROM VIEW_MASTER_LOG_GROUP TAB01
WHERE DATE_FORMAT(ST_LAST_DATE, '%Y-%m-%d') LIKE DATE_FORMAT(NOW(), '%Y-%m-%d');
```

![SQL Plan Case2-1](/img/2012/05/SQL_Plan_Case2-1.png)

Where 조건 날짜 검색 로직을 살펴보면 결과적으로 오늘 0시 이후 데이터를 가져오는 구문입니다. 그렇다면 다음과 같이 변환해 봅시다.

인덱스를 타게 Left Value에서 불필요한 Function을 제거하고, Between으로 0시 이후 데이터를 가져옵니다.

```sql
SELECT *
FROM VIEW_MASTER_LOG_GROUP TAB01
WHERE ST_LAST_DATE BETWEEN DATE_FORMAT(NOW(), '%Y-%m-%d') AND NOW();
```

![SQL Plan Case2-2](/img/2012/05/SQL_Plan_Case2-2.png)

Full Scan이 아닌 Range Scan이며 정상적으로 인덱스를 탑니다.

# Case 3

데이터 추가 조회를 위한 Outer Join 사용 시 주의할 점입니다. 바로 위 1차 변환된 쿼리를 기준으로 말씀 드리겠습니다.

하단 쿼리는 Outer Join이 조건 검색에 영향을 미치지 않고 추가 정보 조회만을 위한 역할로 사용될 때 입니다.

```sql
SELECT
    M.MASTER_NO,
    M.TITLE,
    MI.PATH,
    M.REGDATE,
    CM.TYPE
FROM MAIN AS M
INNER JOIN TAB01 AS CM
    ON CM.MASTER_NO = M.MASTER_NO
LEFT OUTER JOIN TAB02 AS MI
    ON M.MASTER_NO = MI.MASTER_NO
WHERE M.DEL_YN = 'N'
ORDER BY M.MASTER_NO DESC
LIMIT 10000, 10;
```

![SQL Plan Case3-1](/img/2012/05/SQL_Plan_Case3-1.png)

데이터를 10,000번째 위치부터 10 건을 가져온다면 결과적으로 불필요한 10000번 Outer Join이 발생합니다. 쿼리 성능이 상당이 안좋습니다.

물론 데이터가 적을 경우에는 큰 문제가 없지만, 데이터가 누적됨에 따라 서버에 큰 영향을 미칠 수 있습니다. 아래와 같이 수정을 해보죠.

```sql
SELECT
    A.MASTER_NO,
    A.TITLE,
    MI.PATH,
    A.REGDATE,
    A.TYPE
FROM(
    SELECT
        M.MASTER_NO,
        M.TITLE,
        M.REGDATE,
        CM.TYPE
    FROM MAIN AS M
    INNER JOIN TAB01 AS CM
        ON CM.MASTER_NO = M.MASTER_NO
    ORDER BY M.MASTER_NO DESC
    LIMIT 10000, 10
) A
LEFT OUTER JOIN TAB02 AS MI
    ON A.MASTER_NO = MI.MASTER_NO;
```

![SQL Plan Case3-2](/img/2012/05/SQL_Plan_Case3-2.png)

SQL Plan 정보는 더 안좋은 것처럼 보이지만, SQL을 프로파일링 해보면 다음과 같이 좋은 성능을 확인할 수 있습니다.

![SQL Profile Case3](/img/2012/05/SQL_Profile_Case31.png)

변환 후 프로파일은 더욱 길어지기는 했지만, Outer Join을 위한 Sending Data 시간만큼 단축되었습니다.

# Conclusion

3가지 간단한 사례이기는 하지만, SQL 튜닝 시 확인을 해보면 종종 걸리는 문제들입니다. 쿼리 특성에 따라 성능이 좌우되는 만큼 SQL도 서비스 로직을 정확히 파악하여 작성한다면 서버 자원을 효율적으로 배분할 수 있겠죠.

잊지 마세요. MySQL에서는 **단일 코어에서 Nested Loop Join 방식으로 데이터를 처리**한다는 사실을..

재미있는 사례로 다음에 인사 드리겠습니다. ^^