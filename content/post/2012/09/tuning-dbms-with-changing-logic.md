---
title: 서비스 로직 흐름을 변경하여 DB 튜닝을 해보자!
author: gywndi
type: post
date: 2012-09-23T07:43:12+00:00
url: 2012/09/tuning-dbms-with-changing-logic
categories:
  - Oracle
tags:
  - Oracle
  - Performance

---
# Overview

오래전 메가존(현 혜택존) 서비스를 담당하던 시기, 포인트 관련된 부분에서 심각한 성능 저하 및 유효성 취약 문제가 발생하였습니다. 장비 고도화를 통해 관련 문제를 해결하기에 앞서, 서비스 로직 및 테이블 재구성을 통한 최적화 작업을 통해 문제를 해결하였습니다.

이에 관해 간단하게 소개하도록 하겠습니다.

# Problems

다음과 같이 크게 두 가지 문제가 있었습니다.

1. **성능 이슈** 
   - 로그 테이블은 거대한 한 개의 테이블로 구성
   - 데이터 누적에 따라 성능이 급격하게 저하
2. **유효성 이슈** 
   - 자바 어플리케이션에서만 유효성 체크, 비 정상적인 사용 존재
   - 포인트가 현금처럼 사용될 수 있으므로 반드시 필요함

# Solutions

### 1) 파티셔닝을 통한 성능 최적화

오라클 엔터프라이즈 버전에서는 테이블 파티셔닝을 제공하지만, 아쉽게도 오라클 스탠다드에서는 관련 기능이 없습니다. 즉, 어플리케이션 레벨에서 적당히 데이터 분산을 유도하는 방법 밖에는 없습니다. 데이터를 분산하는 방법으로는 여러가지가 존재하겠지만, 저는 월별로 테이블을 분산 저장하는 방식을 사용하였습니다.

매월 하단과 같은 스키마의 테이블을 MCHIP`YYYYMM` 형식으로 생성을 합니다.

물론 해당 월 다음 달로 생성을 해야겠죠?

```
Name            Type
 --------------- ------------
 SEQ             NUMBER
 USER_NO         VARCHAR2(12)
 POINT           NUMBER
 ISSUE_DATE      DATE
 ````

그리고 인덱스 필요 시 데이터 테이블스페이스와는 "물리적으로 분리"된 전용의 테이블스페이스에 생성하여 DISK I/O 비효율도 최소화 유도하였습니다.

데이터 조회는 기본적으로 월별로만 가능하며, 최근 3개월 동안만 조회할 수 있도록 하였고, 필요 시 과거 테이블을 DROP하는 방식으로 변경하였습니다. 만약 최근 3개월 데이터가 필요할 시에는 `UNION ALL` 구문으로 데이터를 가져왔습니다.

다음은 쿼리를 월별로 생성하여 데이터를 저장하는 간단한 자바 프로그램입니다. 저는 SpringFramework 환경에서 구현했었는데, 그것보다는 알아보기 쉬운 단순 자바 프로그램으로 보여드리는 것이 좋을 것 같습니다. (설마 아래 있는 것을 그대로 쓰시는 것은 아니겠죠? ㅎㅎ)

```
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
public class Test {
    public static void main(String[] args) {
        DateFormat df = new SimpleDateFormat("yyyyMM");
        Date date = new Date();

        // 현재 기준 년월
        String yyyymm = df.format(date).toString();

        // 쿼리 생성
        String sql = "INSERT INTO MCHIP"+yyyymm+" \n" +
                "(SEQ, USER_NO, POINT, ISSUE_DATE) \n" +
                "VALUES \n" +
                "(SEQ_MCHIP.NEXTVAL, ?, ?, SYSDATE)";

        System.out.println(sql);
    }
}
````

위와 같이 쿼리를 생성하고, 원하는 테이블에 선별적으로 데이터를 넣습니다. 조회 시에도 위와 같은 방식으로 쿼리를 생성합니다. 만약 한달 이상의 데이터가 필요하다면 UNION ALL로 쿼리를 붙여서 데이터를 조회하면 되겠죠. ^^

### 2) 트리거를 사용한 유효성 체크

포인트 내역을 저장하는 테이블이 있었다면, 포인트 현황을 조회하기 위한 전용 테이블 또한 존재했습니다. 포인트 현황에 저장된 점수가 사용자가 현재 소지하고 있는 포인트이며, 이를 차감하여 서비스에서 사용하는 방식으로 사용하고 있었습니다.

개인 당 한 건의 데이터만 있기 때문에, 사용자 데이터를 조회하는 것에는 큰 무리가 없었지만, 유효성을 자바 어플리케이션에서만 체크했었기 때문에 여기저기 헛점이 많은 상태였습니다. 물론 내구성이 뛰어나게 개발되었다면 큰 문제는 없었겠지만, 협력사가 시간에 쫓겨서 급하게 개발한 산출물인지라.. 아무래도.. ^^;;

자바 소스 전체를 뒤져서 모든 유효성을 체크하는 것은 거의 무리에 가까웠고, 그래서 제가 채택한 방식은 트리거였습니다. 트리거를 사용하여 사용자 포인트 유효성 여부를 DB레벨에서 체크해서 어플리케이션과 분리하자는 의도였죠.

MCHIP201209 테이블에 포인트가 내역이 들어가는 동시에 유효성 체크 후 정상적이면 포인트 현황 테이블에 반영하는 트리거입니다.

```sql
CREATE OR REPLACE TRIGGER TRG01_MCHIP201209
BEFORE INSERT
ON MCHIP201209
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
DECLARE
  POINT NUMBER;
BEGIN
  /*** 현재 사용자 포인트 조회 ***/
  SELECT POINT INTO POINT FROM MCHIP_INFO
  WHERE USER_NO = :NEW.USER_NO;
  … 중략…

  /*** 포인트 유효성 체크  ***/
  IF POINT - :NEW.POINT &lt; 0 THEN
    RAISE_APPLICATION_ERROR(-20001,'Not enough point!!');
  END IF;

  /*** 포인트 현황 업데이트 ***/
  UPDATE MCHIP_INFO SET POINT = POINT + POINT_NEW
  WHERE USER_NO = :NEW.USER_NO;
END;
/
````

# Conclusion

오래전에 성능을 최적화한 내용을 정리하였습니다.

당시 서버에 과부하로 인하여 서버 고도화 및 장비 도입을 위한 투자를 검토 중이었으나, 서비스 로직 재구성 이후 서버가 안정적이었기 때문에 기존 장비로 서비스를 진행하였습니다. 게다가 현재 기존 장비 사용률이 CPU 기준 80~90%였던 상황이 10\~20%로 유지되는 쾌거를 거두었죠.

데이터 처리량을 최소로 유도하는 것이 성능 최적화의 첫걸음이라는 것을 느낀 경험이었습니다.

좋은 포스팅으로 다시 찾아뵐께요^^;