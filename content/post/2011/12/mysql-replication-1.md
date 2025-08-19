---
title: MySQL Replication 이해(1) – 개념
author: gywndi
type: post
date: 2011-12-28T05:14:02+00:00
url: 2011/12/mysql-replication-1
categories:
  - MySQL
tags:
  - DB
  - InnoDB
  - MySQL
  - RDBMS
  - Replication
  - 리플리케이션

---
# Overview

오늘은 조금더 제너럴한 주제를 가지고 정리를 할까합니다.  
바로 MySQL Replication 입니다. MySQL Community에서 유일하게 HA 또는 분산 구성을 할 수 있는 유일한 기능입니다. 물론 [MySQL+DRBD 구성](http://dev.mysql.com/doc/refman/5.5/en/ha-drbd.html)와 같이 HA를 구성하는 방법도 있습니다만, MySQL 제품이 아니므로 스킵~!

먼저 Replication에 대해 간략하게 말씀 드리겠습니다.

# MySQL Replication이란?

MySQL Replication이란 말 그대로 복제입니다. 영어 사전에 나온 듯한 DNA는 아니지만 데이터를 “물리적으로 다른 서버의 저장 공간” 안에 동일한 데이터를 복사하는 기술이죠.

다음 그림은 MySQL Replication을 가장 간단하게 나타낸 그림입니다.  데이터 변경을 마스터 장비에서만 수행하기 때문에 마스터 장애 시에는 전체 노드에 데이터 쓰기 작업이 불가능한 한계가 있습니다.
![MySQL Replicaton Master Slave](/img/2011/12/MySQL-Replicaton-Master-Slave.png)

아래 그림은 MySQL Replication과 Oracle RAC스토리지 구조를 가장 간단하게 묘사한 그림입니다.

![MySQL Replication과 Oracle RAC 비교](/img/2011/12/MySQL-Replication-Oracle-RAC.png)

MySQL복제라는 말과 같이, 디스크를 독립적으로 분리하여 데이터를 유지합니다.

이에 반해 오라클은 RAC 구성 시에는 공유 스토리지(SAN,iSCSI) 장비를 중간에 두고 DB를 이중화 합니다. 엄격하게 다시 말하자면, **MySQL Replication은 데이터를 이중화**하는 것이고, **Oracle RAC는 DB를 이중화하는 개념**입니다.

MySQL은 오직 단일 마스터에서만 데이터 변경 작업을 수행할 수 있고, Oracle은 하나의 스토리지를 중간에 두고 여러 노드에서 데이터 변경 작업이 일어날 수 있습니다.  그렇기 때문에 MySQL에서는 쓰기 부하 분산은 불가능하지만, 읽기 부하 분산은 가능합니다. 그리고 특정 노드 디스크 장애가 전체 데이터 유실로 이어지지 않습니다. 데이터는 **복제**되니까요. Oracle은 어느정도의 읽기/쓰기 부하 분산은 가능하지만 공유 스토리지를 쓰는 만큼 스토리지 장애에는 상당히 취약합니다. 어디까지나, 일반 구성 시 비교를 한 것임을 알아주세요^^

# 마스터, 슬레이브 간 Data 복제 방법

MySQL Replication은 로그 기반으로 비동기적으로 데이터를 복제합니다. 마스터에서는 데이터 변경 작업이 수행되면 Binary Log라는 곳에 이력을 기록을 하는데, Statement, Row 그리고 Mixed 등 세 가지 방식이 있습니다.

* **Statement-based Type**  
MySQL 3.23 이후로 도입된 방식  
실행된 SQL을 그대로 Binary Log에 기록  
Binary Log 사이즈는 작으나, SQL 에 따라 결과가 달라질 수 있음  
(Time Function, UUID, User Defined Function)  

* **Row-based Type**  
MySQL 5.1부터 도입된 방식  
변경된 행을 BASE64로 Encoding하여 Binary Log에 기록  
특정 SQL이 변경하는 행 수가 많은 경우 Binary Log 사이즈가 비약적으로 커질 수 있음  

* **Mixed Type (Statement + Row)**  
기본적으로 Statement-Based Type으로 기록되나, 경우에 따라 Row-base Type으로 Binary Log에 기록

그렇다면 복제는 어떤 방식으로 이뤄질까요? 아래 그림으로 설명 드리겠습니다.

![MySQL에서 데이터 복제 방법](/img/2011/12/how_to_replicate_data_in_mysql.png)

1. Master에서 데이터 변경이 일어나면 자신의 데이터베이스에 반영합니다.
2. Master에서 변경된 이력을 Binary Log에 기록 후 관련 이벤트를 날립니다.
3. Slave IO_THREAD에서 Master 이벤트를 감지하고, Master Binary Log 자신의 Relay Log라는 곳에 기록을 합니다.
5. Slave SQL_THREAD는 Relay Log를 읽고 자신의 데이터베이스에 기록을 합니다. (4,5단계)

기억해야할 사항은 마스터에서는 여러 세션에서 데이터 변경 처리가 가능하지만, **슬레이브에서는 오직 하나 SQL Thread에서만 데이터 변경 처리가 가능**한 점입니다. 그렇기 때문에 마스터에 데이터 변경 트래픽이 과도하게 몰리게 되면 마스터/슬레이브 간 데이터 동기화 시간이 크게 벌어질 수도 있습니다.

# 마치며..

리플리케이션을 잘 활용하면, 부하분산 뿐만 아니라 고가용성 그리고 버전 테스트 등 여러 분야에 멋지게 사용할 수 있습니다. 차근차근 이러한 내용을 정리해서 포스팅하도록 하겠습니다.  
일단, 다음 번에는 실제 리플리케이션 구성 방법에 대해서 먼저 진행할께요^^  
좋은 하루 되세요~!