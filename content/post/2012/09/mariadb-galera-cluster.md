---
title: MariaDB/Galera Cluster 기술 노트!!
author: gywndi
type: post
date: 2012-09-12T06:38:23+00:00
url: 2012/09/mariadb-galera-cluster
categories:
  - MariaDB
  - Research
tags:
  - Galera Cluster
  - MariaDB

---
# Overview

MariaDB에서 MariaDB/Galera Cluster 제품군을 새롭게 출시하였습니다.MariaDB/Galera는 MariaDB의 **Synchronous 방식으로 동작하는 다중 마스터 클러스터**입니다.

MariaDB/Galera Cluster은 Galera 라이브러리를 사용하여 노드 간 데이터 복제를 수행합니다. 물론 아직은 Alpha 버전으로 발표되기는 했지만, 조만간 안정적인 버전이 릴리즈 되면 상당한 물건이 될만한 놈입니다.

오늘은 이에 관해 간단하게 리뷰를 하겠습니다.

# Feature & Benefits

먼저 MariaDB/Galera Cluster의 특징은 다음과 같이 몇 가지로 나눠볼 수 있습니다.

  * Synchronous 방식으로 노드 간 데이터 복제
  * Active-Active 방식의 다중 마스터 구성 모든 노드에서 읽기/쓰기가 가능
  * 클러스터 내 노드 자동 컨트롤 특정 노드 장애 시 자동으로 해당 노드 제거
  * 자동으로 신규 노드 추가
  * 완벽한 병렬적으로 데이터를 행단위로 복제
  * 기존의 MySQL 클라이언트 방식으로 동작

![cluster-diagram1](/img/2012/09/cluster-diagram1.png)
출처 : http://www.percona.com/doc/percona-xtradb-cluster/_images/cluster-diagram1.png

이와 같은 특징에서 전통적인 Asynchronous 방식의 리플리케이션이 가지는 한계점이 해결됩니다.

* 마스터/슬레이브간 데이터 동기화 지연 없음
* 노드 간 유실되는 트랜잭션이 없음
* 읽기/쓰기 모두 확장이 가능
* 클라이언트의 대기 시간이 줄어듬 데이터는 로컬 노드에 존재

하지만 Replication이 가지는 본연의 한계점은 여전히 내재합니다.

* 신규 노드 추가 시 부하 발생 신규 노드 추가 시 모든 데이터를 복사해야 함
* 효과적인 쓰기 확장 솔루션에는 한계 서버 간 Group Communication시 트래픽 발생
* 모든 서버 노드에 동일한 데이터를 유지해야 함 저장 공간 낭비

# MariaDB/Galera Cluster

MariaDB/Galera cluster는 Galera 라이브러리를 사용하여 리플리케이션을 수행한다고 하는데 Galera Replication은 어떤 방식으로 동작할까요?

Galera Replication은 wsrep API로 노드 간 통신을 하며, MariaDB 측에서는 wsrep API에 맞게 내부적인 개선하였다고 합니다. MySQL-wsrep는 https://launchpad.net/codership-mysql에서 시작한 오픈소스 프로젝트입니다.

MySQL-wsrep는 MySQL의 InnoDB스토리지 엔진 내부에서 Write Set(기록 집합 : 트랜잭션의 기록하는 모든 논리적인 데이터 집합)을 추출하고 적용하는 구현됩니다. 노드 간 Write Set을 전송 및 통신을 위해서는 별도의 리플리케이션 플러그인을 사용하며, 리플리케이션 엔진은 wsrep에 정의된 Call/Callback 함수에 따라 동작합니다.

### 1) Synchronous vs. Asynchronous

먼저 Synchronous와 Asynchronous 리플리케이션의 차이점에 대해서 설명하겠습니다.

리플리케이션의 두 가지 방식의 가장 기본적인 차이점은 클러스터 내 특정 노드에서 데이터 변경이 발생하였을 때 다른 노드들에 **동시에 데이터 변경이 적용되는 것**을 보장는지 여부에 있습니다.

Asynchronous 방식의 Replication은 마스터 노드에서 발생한 변화가 슬레이브 노드에 동시에 적용되는 것을 보장하지 않습니다. 마스터/슬레이브 간 데이터 동기화 지연은 언제든 발생할 수 있으며, 마스터 노드가 갑자기 다운되는 경우 가장 최근의 변경 사항이 슬레이브 노드에서는 일부 유실될 수도 있는 가능성도 있습니다.
Synchronous 방식의 Replication은 Asynchronous에 비해 다음과 같은 강점을 가집니다.


* 트랜잭션은 모든 노드에서 동시 다발적으로 발생
* 클러스트 내 모든 노드 간 데이터 일관성을 보장
그러나 Synchronous Replication 수행을 위해서는 2단계 Commit 필요하거나 분산 잠금과 같은 상당히 느린 방식으로 동작합니다.

Synchronous 방식의 Replication은 성능 이슈와 및 복잡한 구현 내부적으로 요구되기 때문에 여전히 Asynchronous 방식의 Replication이 널리 사용되고 있습니다. 오픈 소스 대명사로 불리는 MySQL과 PostgreSQL이 Asynchronous 방식으로만 데이터 복제가 이루어지는 것 또한 그와 같은 이유에서입니다.

## 2) Certification Based Replication Method

성능 저하 없이 Synchronous하게 데이터베이스 리플리케이션을 구현하기 위해 Group Communication and Transaction Ordering techniques이라는 새로운 방식이 고안되었습니다. 이것은 많은 연구자들([Database State Machine Approach](http://library.epfl.ch/theses/?nr=2090) and [Don't Be Lazy, Be Consistent](http://www.cs.mcgill.ca/~kemme/papers/vldb00.html))이 제안했던 방식으로, 프로토타입 구현해본 결과 상당한 발전 가능성을 보여주었던 바가 있습니다.

Galera Replication은 높은 가용성과 성능이 필요한 어플리케이션에서는 상당히 쉽고 확장 가능한 Synchronous 방식의 리플리케이션을 제공하며 다음과 같은 특징이 있습니다.

* 높은 투명성(알기 쉽다는 의미)
* 높은 확장성(어플리케이션에 따라 거의 선형적인 확장까지도 가능)
Galera 리플리케이션은 분할된 라이브러리와 같이 동작하고, wsrep API로 동작하는 시스템이라면 어떠한 트랜잭션과도 연관되어 동작할 수 있는 구조입니다.


## 3) Galera Replication implementation

Galera Replication의 가장 큰 특징은 트랜잭션이 커밋되는 시점에 다른 노드에 유효한 트랜잭션인지 여부를 체크하는 방식으로 동작한다는 점입니다. 클러스트 내에서 트랜잭션은 모든 서버에 동시에 반영되거나 전부 반영되지 않는 경우 둘 중 하나입니다.

![XtraDBClusterUML1](/img/2012/09/XtraDBClusterUML1.png)

트랜잭션 커밋이 가능한 여부는 네트워크를 통해서 다른 노드와의 통신에서 결정합니다. 그렇기 때문에 커밋 시 커밋 요청에 대한 응답 시간이 존재하죠. 커밋 요청에 대한 응답 시간은 다음 요소에 영향을 받습니다.

* 네트워크 왕복 시간
* 타 노드에서 유효성 체크 시간
* 각 노드에서 데이터 반영 시간
여기서 재미있는 사실은 트랜잭션을 시작하는 시점(BEGIN)에는 자신의 노드에서는 Pessimistic Locking으로 동작하나, 노드 사이에서는 Optimistic Locking Model로 동작한다는 점입니다. 먼저 트랜잭션을 자신의 노드에 수행을 하고, 커밋을 한 시점에 다른 노드로부터 해당 트랜잭션에 대한 유효성을 받는다는 것이죠. 보통 InnoDB와 같이 트랜잭션을 지원하는 시스템인 경우 SQL이 시작되는 시점에서 Lock 감지를 하나, 여기서는 **커밋되는 시점에 노드 간 트랜잭션 유효성 체크**를 합니다.

위 그림에서 커밋되는 시점에 마스터 노드에서 슬레이브 노드에 이벤트를 날립니다. 그리고 슬레이브 노드에서 유효성 체크 후 데이터를 정상적으로 반영하게되면 실제 마스터 노드에서 커밋 완료가 되는 것이죠. 그렇지 않은 경우는 롤백 처리됩니다. 이 모든 것은 클러스터 내부에서 동시에 이루어집니다.

## 4) Galera Replication VS MySQL Replication

CAP 모델 관점에서 본다면 **MySQL Replication은 Availability과 Partitioning tolerance**로 동작하지만 **Galera Replication에서는  Consistency과 Availability** 로 동작한다는 점에서 차이가 있습니다. MySQL Replication은 데이터 일관성을 보장하지 않음에 반해 Galera Replication은 데이터 일관성을 보장합니다.

> C Consistency (모든 노드의 데이터 일관성 유지)  
> A Availability (모든 노드에서 항시 Read/Write이 가능해야 함)  정상적으로 작동해야함)

### 5) Limitations

현재는 Alpha 버전으로 릴리즈되었고, 추후 안정적인 버전이 나오겠지만, 태생적으로 가지는 한계가 있습니다.

데이터 일관성 유지를 위해서 트랜잭션이 필요한 만큼, 트랜잭션이 기능이 있는 스토리지 엔진에서만 동작합니다. 현재까지는 오직 InnoDB에서만 가능하다고 하네요. MyISAM과 같이 커밋/롤백 개념이 없는 스토리지 엔진은 데이터 복제가 이뤄질 수 없다는 점이죠.

Row 기반으로 데이터 복제가 이루어지기 때문에 반드시 Primary Key가 있어야 합니다. Oracle RAC와 같이 공유 스토리지에서 동일한 데이터 파일을 사용한다면 Rowid가 같으므로 큰 문제가 없겠지만, 물리적으로 스토리지가 독립적인 구조이기 때문이죠. 이것은 기존 MySQL Replication에서도 주의하고 사용해야할 사항이기도 합니다.

최대 가능한 트랜잭션 사이즈는 wsrep\_max\_ws\_rows와 wsrep\_max\_ws\_size에 정의된 설정 값에 제약을 받으며, LOAD DATA INFILE 처리 시 매 1만 건 시 커밋이 자동으로 이루어집니다.

트랜잭션 유효성이 커밋되는 시점에서 이루어지며, 동일한 행에 두 개의 노드에서 데이터 변경을 시도한다면 오직 하나의 노드에서만 데이터 변경이 가능합니다.

또한 원거리 리플리케이션 경우 커밋에 대한 응답 요청으로 인하여 전반적인 시스템 성능 저하가 발생합니다.

# Conclusion

MariaDB/Galera Cluster은 전통적인 MySQL Replication이 가지는 가장 큰 문제점이었던 **데이터 동기화 지연과 노드 간 트랜잭션 유실 가능에 대한 해결책**을 제시합니다.

또한 노드 내부에서는 InnoDB 고유의 트랜잭션으로 동작하고, 실제 커밋이 발생하는 시점에 다른 노드에게 유효성을 체크 및 동시 커밋한다는 점에서 재미있는 방식으로 동작하죠. 결국 기존 MySQL 아키텍트는 그대로 유지하고, Replication 동작에 관한 방법만 수정하여 RDBMS 기반의 분산 DBMS 를 내놨다는 점에서 상당히 흥미로운 제품입니다.

그러나, 동일한 데이터 변경 이슈가 많은 서비스 경우 노드 간 데이터 충돌이 자주 발생 가능성이 있을 것으로 판단됩니다. 데이터 충돌이 발생하여 자주 트랜잭션 롤백이 발생하면 사용자 별로 원활한 서비스 사용이 불가하니, 이에 대한 대책을 어플리케이션 레벨에서 적절하게 고려하여 서비스 설계를 해야 하겠죠. 예를 들어 노드 단위로 주로 변경할 데이터를 나눠서 처리하는 방식으로 서비스 설계가 이뤄져야하지 않을까 생각합니다.

Synchronous 방식으로 노드 간 데이터 복제가 이루어진다는 점에서 아주 반가운 소식이기는 하지만, 기존과 같이 데이터를 설계하면 오히려 서비스 안정성이 크게 떨어질 수도 있다는 점에서 새로운 변화가 예상됩니다.

관련 벤치마크와 안정성 검토가 반드시 필요합니다. 데이터는 거짓말을 하지 않으니..^^

감사합니다.