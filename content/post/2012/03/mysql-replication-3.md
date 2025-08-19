---
title: MySQL Replication 이해(3) – 활용
author: gywndi
type: post
date: 2012-03-17T09:19:07+00:00
url: 2012/03/mysql-replication-3
categories:
  - MySQL
tags:
  - MySQL
  - Replication

---
# Overview

MySQL Replication 시리즈 마지막 3탄, 활용에 관한 포스트입니다. 앞 선 시리즈 [Permanent Link to MySQL Replication 이해(1) – 개념](/2011/12/mysql-replication-1/)와 [Permanent Link to MySQL Replication 이해(2) – 구성](/2012/02/mysql-replication-2/)에서 기본적인 개념과 구성을 다뤘다면, 이 자리에서는 실제적으로 어떤 분야에 활용할 수 있는지 설명드리겠습니다.

1. **Scale Out**
2. **High Availability**
3. **Data Partitioning**

자, 그럼 시작해볼까요?

# Scale out

MySQL Replication이 가장 많이 활용되는 분야입니다.  
MySQL Replication은 READ관련 Scale out만 가능합니다. 만약 WRITE 이슈가 있다면, MySQL 레벨에서는 Scale out이 불가합니다. 특히나 Replication 운영 시 마스터 트래픽이 과도하게 발생하면, Master와 Slave 간 데이터 동기화 지연 현상이 발생합니다. [Permanent Link: 반드시 알아야할 MySQL 특징 세 가지](/2011/12/mysql-three-features/) 내용을 읽어보시면 이해가 조금더 수훨하겠네요.^^

![MySQL Replication Scale Out](/img/2012/03/MySQL_Replication_Scale_Out1.png)

WRITE 관련 Scale out이 불가하다고 했었는데, 전혀 불가능한 것일까요? 그렇지 않아요~! 서버 구성을 적절하게 재배치한다면 WRITE 분산도 일부 가능합니다.

* 다중 마스터 구성 (하단 High Availability 참고)  
  기본적으로 MySQL에서는 다중으로 마스터를 구성할 수 없습니다. 각 슬레이브들은 오직 하나의 슬레이브만 가질 수 있습니다.
* 피라미드형  구성 (하단 Data Partitioning 참고)  
  역할에 따라서 서버를 재배치하는 방식입니다. 모든 서버가 가져야할 데이터 공유는 최상위 마스터에서 담당하고, 중간 슬레이브는 자신이 맡은 역할에 맞는 마스터 역할을 하는 것이죠.

# High Availability

MySQL Replication 을 높은 가용성 구현을 위해서 사용할 수 있습니다.  아래와 같이 가상 아이피(Virtual IP)를 통해서 App서버들이 서비스를 제공하고 있다면 마스터 장비 장애 발생 시자동으로 Virtual IP가 유휴 슬레이브 장비로 Virtual IP를 넘겨서 장애를 빠르게 대비할 수 있습니다.

![High Availability](/img/2012/03/High_Availability.png)

일단 슬레이브로 마스터 역할이 넘어간 시점부터는 현재 데이터의 기준은 신규 마스터이어야 합니다. 데이터가 비동기적으로 복제되는 구조이기 때문에, 장애 후 IP가 넘어가는 일시적인 시점 동안 트랜잭션 유실은 발생할 수 있다는 점 있지 마세요^^

서버 한 대 효율을 조금 더 올리고자 한다면, 아래와 같이 구성해보는 것은 어떨까요?

![High Availability : Multi-Master](/img/2012/03/High_Availability-Multi-master.png)

문제는 동일 데이터 변경에 관한 이슈인데, 이것은 Service1 과 Service2 데이터베이스를 물리적으로 분리하시면 됩니다.

# Data Partitioning

분명 MySQL Replication에서 Slave는 하나의 Thread로만 SQL을 실행하기 때문에, 서버 간 동기화 지연 현상이 발생합니다. 하지만 서버 구성을 조금만 변경한다면 어느정도는 해결할 수 있습니다.

![Master Scale-out](/img/2012/03/Master-Scale-out.png)

Replicate\_Do\_DB 혹은 Replicate\_Do\_Table 옵션을 사용하여, 실제로 적용할 객체들만 선별적으로 동기화하는 것입니다. 서비스 단위로 기능을 나눌 수도 있고, 역할 별로 기능을 나눌 수 있습니다.

```bash
$ vi /etc/my.cnf
replicate-do-db=common
```

단, 서버 확장을 고려하여, 서비스 설계 단계부터 Database  또는 테이블을 최대한 물리적으로 분리하여 설계하는 것이 가장 중요합니다.

# Conclusion

위에서 설명드린 것은 극히 일부일 뿐 더욱 다양한 케이스에 Replication을 활용할 수 잇습니다. 예를 들어 DB Major 버전 업그레이드(ex: 5.1.x -> 5.5.x), 테이블 구조 변경, 테스트 환경 구성 등이 바로 그것들입니다. MySQL Replication은 물리적으로 저장소가 분리된 영역에 데이터를 비동기적으로 복제하는 원리만 꼭 기억하세요. ^^

위 설명에서는 추상적으로 언급 드렸으나, 추후 실제 구성 사례를 정리해서 꼭 공유 드릴께요^^