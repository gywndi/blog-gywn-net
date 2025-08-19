---
title: 하루 2.5억 트윗을 저장하는 트위터의 새로운 저장 스토어
author: gywndi
type: post
date: 2012-03-08T01:46:30+00:00
url: 2012/03/new-tweet-store
categories:
- MySQL
- NoSQL
- Research
tags:
- Gizzard
- MySQL
- Replicate
- Sharding
- Snowflake
- Tweet
- Twitter

---
# Overview

트위터는 하루 평균 2.5억 건의 트윗을 저장한다고 합니다. 과거 트위터는 날짜 기준으로 데이터를 분할 관리하여 저장을 하였고, 대략 3주에 한번씩 서버를 추가하여 Scale-out 하였습니다.

하지만 이 방식에는 다음과 같은 문제가 있었습니다.

1. **부하 분산**
2. **고비용**
3. **복잡한 프로세스**

문제를 해결하기 위해서 트위터에서 New Tweet Store를 고안했다고 합니다.

자, 그럼 기존 문제점부터 차근차근 알아보도록 합시다^^;

# Problems

* **부하 분산(Load Balancing)**  
날짜 기준으로 데이터를 나눠서 분산 저장 및 관리하기 때문에, 시간이 지날수록 과거 데이터 조회 건수는 비약적으로 낮아집니다. 특히 대부분의 데이터 조회 요청은 현재 시각 기준으로 들어오기 때문에, 데이터 읽기 HOTSPOT이 발생할 수 밖에 없습니다. 
![Load Balancing Problem](/img/2012/03/old_load_balancing.png)

* **고 비용(Expensive)**  
데이터는 나날이 쌓여만 가고 이를 위해서는, 매 3주에 걸쳐서 신규 노드를 추가해줘야 합니다. 신규 노드는 서버 한 대가 아닌 마스터/슬레이브로 구성되기 때문에 상당한 비용이 소요됩니다. 
!(Expensive Problem)[/img/2012/03/old_expensive.png]

* **절차 복잡성(Logistically complicated)** 
![Logistically Complicated Problem](/img/2012/03/old_complicated.png)

# NEW Tweet Store

트위터는 당면한 문제를 해결하기 위해 데이터 분산 도구로는 Gizzard, 데이터 저장소로는 MySQL, 그리고 UUID 생성에는 SnowFlake등으로 새롭게 데이터 분산 재구성 하였습니다.
![Twitter's New Tweet Store](/img/2012/03/New_tweet_store.png)

결과적으로 기존의 과거 날짜 기반의 데이터 축적에서 점진적으로 데이터가 축적되는 효과를 가져왔으며, 3주에 한번씩 고된 업무를 기획하고 이행해야했던 복잡한 절차도 사라졌다고 합니다.

전체적인 트위터 동작에 관한 내용을 하단 그림으로 표현해봅시다.
![New Tweet Store Architect](/img/2012/03/New_tweet_architect.png)

트윗이 저장되는 저장소를 T-Bird, 보조 인덱스가 저장되는 저장소를 T-flock라고 내부적으로 지칭합니다. 두 시스템 모두 Gizzard 기반으로 이루어져 있으며, Unique ID는 Snowflake로 생성을 합니다.

그러면 New Tweet Store에 적용된 Gizzard, MySQL, Snowflake에 관해서 알아보도록 하겠습니다.

* **Gizzard in New Tweet Store**  
Gizzard는 데이터를 분산 및 복제해주는 프레임워크입니다. 클라이언트와 서버 사이에 위치하며 모든 데이터 요청을 처리합니다. **데이터 분산** 및 **복제 관리** 뿐만 아니라 **데이터 이관**, **장애 대처**등 다양한 역할을 수행합니다. 
![Gizzard Architect](/img/2012/03/Gizzard.png)

가장 큰 특징은 Write연산에 관해서는 **멱등성 및 가환성** 원칙에 의해 적용된다는 점입니다. 기본적으로 Gizzard는 데이터가 저장되는 순서를 보장하지 않습니다. 이 말은 곧 언제든지 예전 Write 연산이 중복되어 다시 수행될 수 있음을 의미하는데, 중복 적용될 지라도 최종적인 데이터 일관성을 보장합니다.

* **MySQL in New Tweet Store**  
MySQL이 저장소로 사용됩니다. 물론 Gizzard에서 다른 다양한 저장소를 지원하지만, 트위터에서는 일단 MySQL로 스토리지 엔진은 InnoDB로 선택해서 사용하였습니다. InnoDB 스토리지엔진을 사용한 이유는 행단위 잠금과 트랜잭션을 지원하기 때문데, 다른 스토리지 엔진 대비 데이터가 망가질 확률이 훨씬 적기 때문이 아닐까 추측해 봅니다.각 MySQL 서버에 관한 하드웨어 사양과 데이터 사이즈는 다음과 같습니다.

![MySQL Server Spec](/img/2012/03/MySQL_Server_Spec.png)
MySQL 관련된 가장 특이한 사항은 정말 단순 데이터 저장 용도로만 사용된다는 점입니다. 일반적으로 MySQL에서 데이터 복구와 이중화를 위해서 Binary Log를 사용하지만, Gizzard와 함께 사용되는 MySQL은 이 기능마저 사용하지 않습니다. 게다가 데이터 복제를 위해서 MySQL 고유의 Replication 기능마저 사용하지 않는다는 점에서, MySQL은 new tweet store에서는 단순한 데이터 저장 수단인 것을 알 수 있었습니다.  
그 이유는 **Gizzard가 데이터 분산 및 복제 모두를 수행**하기 때문입니다.

* **Snowflake in New Tweet Store**  
Snowflake는 New Tweet Store에서 고유 아이디 값(Unique ID)을 할당하는 역할을 합니다. 총 8Byte로 구성되어 있으며 시간 순으로 정렬 가능한 값입니다. 
![Snowflake](/img/2012/03/Snowflake.png)

Time 41 bits : millisecond이며 앞으로 최대 69년 사용할 수 있음  
Machine id 10 bits : 1024 대의 머신에 할당 가능  
Sequence number 12 bits : 머신당 같은 millisecond에 4096개 생성 가능

# 마치며..

작년 Amazon RDS에 서비스를 올리기 위해서 아래와 같이 구상을 한 적이 있습니다. Amazon RDS 상 제약사항을 회피하고자 한 것으로, 기본적으로 공통으로 필요한 정보만 공유하자는 컨셉이었습니다. 변경 로그는 멱등성을 가지며 주기적(1초)으로 각 서비스 DB에서 변경 로그들을 Pulling하여 데이터 일관성을 유지하자는 내용이었습니다.

![Datastore Concept](/img/2012/03/Datastore_concept_in_KTH.png)

트위터 사례는 참으로 많은 점을 느끼게 하였습니다. 결과적으로 새롭게 데이터 분산을 재구성하여 점진적인 데이터 증가와 더불어 DBA 팀 자체 업무가 크게 줄었다는 사실에서 깊은 찬사를 보냅니다.

감사합니다.

참고자료)  
- http://highscalability.com/blog/2011/12/19/how-twitter-stores-250-million-tweets-a-day-using-mysql.html
- https://github.com/twitter/gizzard
- https://github.com/twitter/snowflake