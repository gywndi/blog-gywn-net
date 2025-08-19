---
title: DB Link와 Export/Import를 활용한 데이터 이관 성능 리포트
author: gywndi
type: post
date: 2012-04-13T07:41:39+00:00
url: 2012/04/migration_with_dblink_exp_imp
categories:
  - Oracle
  - Research
tags:
  - Migration
  - Oracle

---
안녕하세요. 한동안 MySQL에 빠져 있다가, 최근 Oracle 데이터 이관 작업 도중 재미난 사례 공유 합니다. DB Link를 통한 CTAS(Create Table As Select)와 Export/Import를 통한 데이터 이관 비교입니다.

# 서비스 요구 사항

- 서비스 DBMS 버전 : Oracle 9i  
- 전체 데이터 파일 사이즈 : 120G (인덱스 포함)  
- 타겟 테이블 데이터 사이즈 : 26G (인덱스 제외)  
- 네트워크 속도 : 100Mbps (max: 12.5MB/s)  
- 일 1회 현재 서비스 데이터 동기화 수행  
- 모든 작업은 `자동화`하여 운영 이슈 최소화

위 환경을 고려하였을 때, 전체 데이터 파일 Copy는 동기화 시간 및 스토리지 낭비 요소가, Archive Log 활용하기에는 운영 이슈가 존재했습니다.

그래서 결정한 것이 필요한 테이블만 이관하자는 것이고, 가장 효율적인 방안을 모색하기 위해 DB Link와 Import/Export 두 가지 성능을 비교해보았습니다.

# DB 환경 구축

Oracle DBMS 환경은 장비 효율을 높이기 위해서 Oracle VM 상에 가상 머신으로 구성을 하였습니다. Oracle VM에 대한 소개는 추후 천천히 소개를 드릴께요^^
![서버 구성](/img/2012/04/Server_Architect1.png)

# Export/Import 결과

아래 그림과 같이 nfs Server/Client 구성을 하였는데, 타겟 테이블을 별도로 Export 후, 해당 파일을 nfs로 직접 끌어와서 데이터를 가져오는 방식입니다.
![Export/Import를 위한 nfs 서버 구성](/img/2012/04/Exp_Imp_nfs_architect.png)

Export 시간은 약 20분, Import시간은 약 60분 그리고 사전 작업 시간을 고려해봤을 때, 데이터만 이관할 시 90분이라는 시간이 소요되었습니다. 하루에 1시간 30분 정도 동기화 시간을 제공하면 되니 크게 나쁜 결과는 아니었습니다.

그러나 Import 수행되는 동안 alert.log를 확인을 해보니 Log Switch가 너무 빈도있게 발생(1분 단위)하였으며, 아래와 같이 Log가 데이터 파일로 Flush되지 않아서 대기하는 상황이 발생하였습니다.
![Import 시 Alert 로그 현황](/img/2012/04/Exp_Imp_Alert_Log.png)

# DB Link 결과

Export/Import 시간 체크 후 Redo Log 사용 없이 직접적으로 데이터를 Write할 수 있다면 더욱 빠른 데이터 이관이 가능할 것이라고 판단이 되어 이번에는 DB Link를 통한 CTAS(Create Table As Select) 방법으로 접근을 해보았습니다. 물론 CTAS에서 반드시 NOSLOGGING 옵션을 줘야겠죠 ^^

Oracle VM 서버에서 환경에 맞게 계정 별로 DB Link를 생성을 하고 하단과 같이 테이블 Drop 후 `Create Table As Select` 구문을 실행합니다.

```sql
SQL> DROP TABLE TABLE01;
SQL> CREATE TABLE TABLE01 NOLOGGING
   > AS
   > SELECT * FROM TABLE01@DB_LINK;
```

Oracle VM에서는 물리적으로 다른 장비 세 대로부터 동시에 데이터를 받으며, 물리적인 장비 안에는 각각 두 개의 서비스 계정이 포함됩니다.

결과는 다음과 같습니다.
![DB Link Result](/img/2012/04/DB_Link_Result1.png)

위와 마찬가지로 동시에 실행을 했기 때문에 가장 오래 걸린 서비스가 최종 소요된 시간이며, 00:00~ 00.19:13 에 종료되었으니 대략 20분 소요되었습니다. 앞선 결과에서 90분 소요되던 것을 20분으로 줄였으니, 상당히 괜찮은 결과이네요^^

물론 Alert Log에 Log Switch 관련 메시지는 나오지 않았습니다.

# Conclusion

DB Link를 활용하여 데이터를 이관하는 것이 압도적으로 빠른 결과였습니다.

그러나 항상 DB Link가 좋은 것은 아닙니다. 다행히 대상 테이블에는 LOB 관련 필드는 없었지만, 만약 LOB 필드가 있었다면 어쩔 수 없이 Export/Import 방식을 써야만 했겠죠.

데이터 이관을 위한 여러가지 방안이 있겠지만, 한번 쯤은 두 가지 방법의 장단점을 따져보고 싶었는데 좋은 기회가 되어서 내용 공유 드립니다.