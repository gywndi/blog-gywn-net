---
title: MariaDB의 FederatedX를 소개합니다.
author: gywndi
type: post
date: 2014-12-05T13:53:39+00:00
url: 2014/12/let-me-introduce-federatedx
categories:
  - MariaDB
tags:
  - Federated
  - MariaDB

---
# Overview

MySQL에는 Federated라는 스토리지 엔진이 있는데, 이는 원격의 테이블에 접근하여 제어하기 위한 용도로 사용됩니다.  얼마 전 이 엔진과 관련하여 재미있는 테스트를 하였는데, 이 내용을 소개하기에 앞서서 간단하게 정리해보도록 하겠습니다.

# Features

FederatedX는 사실 MariaDB에서 Federated 엔진을 의미하는데, 이를 다른 이름으로 구분하는 것은 사실 더욱 확장된 기능을 가지기 때문입니다.

1. **원격 서버 접근**  
  원격에 있는 테이블을 로컬에 있는 것처럼 사용
2. **트랜잭션**  
  2-Phase Commit 형태로 데이터의 일관성을 유지
3. **파티셔닝**  
  각 파티셔닝 별로 다른 원격 테이블 참조 가능

# Usage

FederatedX 스토리지 엔진은 MariaDB에서는 기본적으로는 활성화되어 있습니다. MySQL에서는 별도의 옵션을 줘야만 활성화되는 것과는 다른 측면이죠.

테이블 생성 방법은 URL/아이디/패스워드를 모두 지정하여 생성하는 방법과, SERVER를 추가해서 사용하는 방법 두 가지가 있습니다.

## 1) Server 정보를 통한 테이블

CREATE SERVER 구문으로 원격 테이블 접속에 대한 설정을 등록하는 방식입니다. FederatedX 테이블을 사용하기에 앞서서 서버 정보를 등록합니다.

```sql
CREATE SERVER 'remote' FOREIGN DATA WRAPPER 'mysql' OPTIONS
(HOST 'remote',
 DATABASE 'target_db',
 USER 'appuser',
 PASSWORD 'passwd123',
 PORT 3306,
 SOCKET '',
 OWNER 'appuser');
```

위에서 등록한 서버 정보를 활용하여 FederatedX 테이블을 생성합니다.

```sql
CREATE TABLE `tb_remote` (
`col01` bigint(20) NOT NULL,
`col02` bigint(20) NOT NULL,
`col03` varchar(20) NOT NULL DEFAULT '',
PRIMARY KEY (`col01`)
) ENGINE=FEDERATED
CONNECTION='remote';
```

## 2) URL을 통한 테이블 생성

반드시 위와 같이 서버를 등록하고 FederatedX 테이블을 생성할 필요는 없습니다. 별다른 메타 정보 없이 직접 원격의 서버에 Connection 정보를 명시적으로 선언을 하여 FederatedX 테이블을 생성할 수 있습니다.

```sql
CREATE TABLE `tb_local` (
`col01` bigint(20) NOT NULL,
`col02` bigint(20) NOT NULL,
`col03` varchar(20) NOT NULL DEFAULT '',
PRIMARY KEY (`col01`)
) ENGINE=FEDERATED
connection='mysql://target_db:passwd123@remote:3306/target_db/tb_remote';
```

Connection은 `mysql://사용자:패스워드@호스트:포트/데이터베이스/테이블` 형태로 주면 되겠죠? ^^

## 3) 파티셔닝 테이블 구성

생성하는 방법을 알았으니, 이제 실제로 테이브을 생성해보도록 해보아요.

각 파티션 별로 직접 커넥션 정보를 명시하여 접근할 수 있겠지만.. 여기서는 서버를 등록하는 방식으로 예를 들도록 할께요.

먼저 서버 정보를 등록합니다.

```sql
CREATE SERVER 'remote1' FOREIGN DATA WRAPPER 'mysql' OPTIONS
(HOST 'remote1',
 DATABASE 'target_db',
 USER 'appuser',
 PASSWORD 'passwd123',
 PORT 3306,
 SOCKET '',
 OWNER 'appuser');

CREATE SERVER 'remote2' FOREIGN DATA WRAPPER 'mysql' OPTIONS
(HOST 'remote2',
 DATABASE 'target_db',
 USER 'appuser',
 PASSWORD 'passwd123',
 PORT 3306,
 SOCKET '',
 OWNER 'appuser');

CREATE SERVER 'remote3' FOREIGN DATA WRAPPER 'mysql' OPTIONS
(HOST 'remote3',
 DATABASE 'target_db',
 USER 'appuser',
 PASSWORD 'passwd123',
 PORT 3306,
 SOCKET '',
 OWNER 'appuser');
```

그리고, 타 스토리지 엔진의 파티셔닝 테이블을 생성하는 형태로 테이블을 생성합니다.

```sql
CREATE TABLE `tb_remote` (
`col01` bigint(20) NOT NULL,
`col02` bigint(20) NOT NULL,
`col03` varchar(20) NOT NULL DEFAULT '',
PRIMARY KEY (`col01`)
) ENGINE=FEDERATED
PARTITION BY RANGE (col01)
(PARTITION p1000 VALUES LESS THAN (1001) CONNECTION='remote1',
 PARTITION p2000 VALUES LESS THAN (2001) CONNECTION='remote2',
 PARTITION p3000 VALUES LESS THAN (3001) CONNECTION='remote3');
```

아, 여기서 추가로 각 파티셔닝 정의에 Connection 정보, 여기서는 서버 정보를 같이 명시하여 테이블을 생성하면.. FederatedX를 통한 파티셔닝 테이블 완성~! 참 쉽죠잉??

# Caution?!!!!

얼뜻, 보면 굉장해 보이는 기능입니다. FederatedX를 사용하면, 원격의 다수의 테이블에 접근을 할 수 있는 형태가 되기 때문, 굉장한 트래픽을 분산 형태로 처리할 수 있다는 기대감을 강력하게 뿜어냅니다. 자, 그럼 서비스에서 사용할 수 있을까요?? 제 대답은 강력한 NO입니다. 왜그러나고요?

자 간단하게 아래와 같이 LIMIT구문으로 한 건만 가져오는 쿼리를 실행한다고 한다면.. 특히, 개발 툴에서 누구나 쉽게 아래와 같이 쿼리를 질의를 하겠죠.

```sql
select * from tb_remote limit 1;
```

문제는, 모든 인덱스에 대한 실질적인 정보는 원격에 테이블에 있다는 점에 있습니다. FederatedX는 단지 어떤 식으로 테이블이 구성되어 있다는 대략적인 스키마 정도만 알고 있을 뿐, 결코 원격의 테이블에 있는 데이터 분포도 혹은 핸들러와 같은 오브젝트에 접근할 수 없습니다.

![Federated Explain](/img/2014/10/Federated-Explain.png)

Federated 경우 데이터가 물리적으로 엄격히 다른 타 서버에 존재하기 때문에, 데이터 처리 시 필요한 모든 데이터를 네트워크로 받아와야 합니다. 즉, 잘못하면 네트워크 대역폭을 한방(?)에 가득 채울 수도 있고, 쿼리 처리 또한 굉장히 버벅댈 수 밖에 없습니다.

# Conclusion

지금까지 MariaDB의 Federated 엔진에 대해서 간단하게 살펴보았습니다.

위에서는 주의사항만 말해놓았지만, 사실 분포도가 아주 좋은 인덱스(예를 들면 Primary Key)를 통한 데이터 접근 시에는 전혀 문제가 되지 않습니다. 그렇지만, 모든 상황에서 인덱스를 고집할 수 있는 상황이기 때문에, 서비스에서 조회 용도로 사용하기에는 대단히 위험합니다.

만약 피치못할 사정에 활용을 해야한다면, 이 테이블을 통한 데이터 접근은 반드시 엄격하게 제어를 하여 사용하시기 바랍니다.