---
title: 아마존의 가상 RDBMS인 Amazon RDS의 특성 몇 가지
author: gywndi
type: post
date: 2012-08-10T05:26:37+00:00
url: 2012/08/amazon-rds-feature
categories:
  - Cloud
  - MySQL
tags:
  - Amazon RDS
  - MySQL

---
# Overview

지난 해 말 글로벌 서비스를 겨냥하여 Amazon 가상 플랫폼 상에 인증 서비스를 오픈하였고, 올해 초에는 푸딩.투 서비스 또한 런칭하여 서비스 중에 있습니다.

글로벌 서비스를 위한 저장소로는 아마존에서 제공하는 가상 관계형 DBMS인 Amazon RDS를 사용 중입니다.

이번 포스팅에서는 Amazon RDS에 대한 특성 몇 가지를 설명 드리겠습니다.

# Virtual Database Instance

**Amazon RDS는 Virtual Database Instance입니다.** 

DBMS는 데이터를 처리하는 미들웨어이고, 미들웨어는 OS 기반 위에서 동작합니다. 일반적인 상황이라면 OS에 접근하여 그에 맞게 DBMS를 설치하고, 관련 파라메터도 정의를 해야만 하지만, 모든 것이 "웹 콘솔" 상에서 간단하게 처리합니다.

웹 콘솔에서 **“Launch DB Instance”** 버튼을 누르면 하단과 같은 레이어가 나오는데, 사용할 DBMS를 선택하고 DB 인스턴스 정보 몇가지만 입력하여 생성을 하면 10분 안에 즉시 사용 가능합니다.

![[Amazon RDS] Launch DB Instance Wizard](/img/2012/08/Amazon-RDS-Lanuch-DB-Instance-Wizard.png)
MySQL, Oracle, SQL Server 등 일반적으로 많이 사용하는 DBMS를 사용할 수 있습니다. (2011년 중반에는 SQL Server는 제공하지 않았습니다. ^^)

가상 DB 인스턴스이기 때문에 직접적으로 OS에 접근하여 조작은 불가합니다. DB 튜닝을 위해 파라메터를 변경하는 경우에도 직접적으로는 불가하며, rds-cli라는 클라이언트 툴을 사용해서 조작해야 합니다.

다음은 Slow Log를 사용할 수 있도록 설정하는 간단한 샘플입니다.

```
rds-modify-db-parameter-group testDB \
--region us-west-1 \
--parameters "name=slow_query_log, value=on, method=immediate"
```

이런 사항들이 불편함으로 다가올 수 있겠지만, 모든 OS관련된 사항들을 RDS 클라이언트 API Call을 통해서 이루어지고, 특별히 OS에 대해서 관리할 사항 또한 없기 때문에 상당 부분 DB 운영 이슈가 사라집니다.

# Multi-AZ (Availablity Zone)

**Amazon RDS에서 High Availablity를 구현하는 대표적인 방법입니다.**

가용 Zone에 두 개의 인스턴스(기본 인스턴스/예비 인스턴스)를 띄우고, 기본 인스턴스DB에서 데이터 변경 즉시 동기화합니다. Replication이 비동기적인 방식으로 동작하지만, Multi-AZ은 동기화 방식이라는 점에서 큰 차이가 있습니다.

MySQL Replication의 고질적인 문제인 실시간 데이터 동기화 지연 문제와, 장애 시 빠른 복구가 어려운 문제를 단번에 해결할 수 있는 방안이죠.

하지만 꼭 기억해야할 몇가지 사항이 있습니다.

**첫째 Multi-AZ 기능은 High Availablity 구현을 위한 방법입니다.**

예비 인스턴스는 단지 기본 인스턴스에서 일어난 이벤트를 적용할 뿐 Read/Write 트래픽을 분산하지 않습니다. Read는 바로 아래에서 설명할 Replication으로 어느정도 분산이 가능하나, Write 은 데이터 Sharding 기법 외에는 방법이 없습니다.

![[Amazon RDS] Multi-AZ](/img/2012/08/Amazon-RDS-Multi-AZ.png)

**둘째 Multi-AZ은 같은 Region에서만 구성 가능 합니다.**

Amazon RDS에는 Region과 Zone 개념이 있습니다.

Region은 “미국 서부 캘리포니아”, “일본”, “싱가폴” 등과 같이 큰 대륙 혹은 지역을 의미합니다. 그리고 대륙 간에는 인터넷 라인으로 연결되어 있습니다.

Region 안에는 여러 개의 Zone이 있습니다. Zone은 Region에 포함된 몇 개의 IDC 센터입니다. 각 Zone은 전용선으로 연결되어 있으며, 지역적으로 수십 혹은 수백 킬로미터 떨어져 있습니다.

![[Amazon RDS] Multi-AZ(2)](/img/2012/08/Amazon-RDS-Multi-AZ2.png)

Zone 사이에는 전용선으로 데이터 전송 속도 및 신뢰성이 보장되기 때문에, 기본 인스턴스 반영 시 즉각적인 동기화가 가능합니다.

그러나 Region는 상황이 다릅니다. 인터넷 망으로 연결되어 있기 때문에, 데이터 동기화가 즉시 불가한 것이죠.

# Data Replication

Amazon RDS에서 Multi-AZ이 HA 구현을 위한 방법이라면, DB Scale-Out을 위한 방안으로는 전통적인 MySQL의 복제 기술, 즉 MySQL Replication을 제공합니다. 슬레이브 DB를 추가하는 방법은 간단합니다. 웹 콘솔에서 “Create Read Replica” 버튼을 누르고 몇가지 정보만 넣으면 됩니다.

인스턴스에서는 최대 5개의 복제 서버를 가질 수 있으며, 데이터는 MySQL Replication과 동일하게 비동기적으로 일관성이 유지됩니다. 즉, 언제든지 마스터/슬레이브 간 데이터 동기화 지연 현상이 발생할 수 있습니다.

# 제약 사항

Amazon RDS에서는 다음과 같은 몇 가지 제약 사항이 있습니다.

  1. DB 인스턴스는 최대 10 개까지 생성 가능
  2. DB 인스턴스 별 최대 가능한 스토리지는 1TB
  3. 각 DB 인스턴스의 복제서버는 최대 5개까지만 생성 가능
  4. Multi-AZ은 동일한 가용 존 내에서만 사용 가능

# Conclusion

전체가 아닌 일부 특성만을 적어놓기는 했지만, 간단한 개념 잡기에는 충분하다고 생각합니다. ^^;;

Amazon RDS 사용을 하면 DB 시스템적인 운영 이슈가 최소화되기 때문에 굉장히 편리합니다. 하지만 몇 가지 제약 사항으로 인하여 제대로 사용을 하지 못하면 큰 낭패를 볼 수 있습니다. 또한 간단한 DB 성능 테스트 면에서도 동일한 스펙의 물리 서버 성능의 1/3 정도만 발휘하는 것으로 나타났습니다.

이제 정말로 시스템 성능이 아닌 DBA 자체의 개발 역량이 중요시되는 추세인 것 같네요.

공부를 더욱더 열심히 해야 살아남겠군요. ^^;;