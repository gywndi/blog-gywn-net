---
title: Vitess, 로컬에서 직접 만들어보며 이해하기
subtitle: 
author: admin
type: post
date: 2026-08-09T23:15:14+09:00
url: 2026/08/vitess-from-scratch-bare-metal-sharding
categories:
  - IT
tags:
  - mysql
  - IT
  - vitess
---

MySQL 하나로는 데이터를 감당하기 힘들어지는 시점이 옵니다. 유튜브, 슬랙, 깃허브 같은 곳들이
이 문제를 풀 때 쓴 방법 중 하나가 Vitess입니다. Vitess가 뭘 하는 물건인지, 어떤 부품으로
이뤄져 있는지, 그 부품들을 실제로 어떻게 배치해야 하는지를 로컬 Docker 환경에 직접
만들어보면서 정리했습니다. 여기 나오는 구성은 [GitHub 저장소](https://github.com/gywndi/vitess-example)에
그대로 올려뒀고, Docker만 있으면 그대로 따라 켤 수 있습니다.

---

## 1. Vitess가 뭔가요?

MySQL 하나로는 데이터가 너무 커지거나 쓰기 트래픽이 너무 많아지는 순간이 옵니다. 이때 흔히
쓰는 해법이 샤딩입니다. 데이터를 여러 MySQL로 쪼개서 나눠 담는 거죠. 문제는 샤딩을 직접
하면 애플리케이션 코드가 "이 데이터가 몇 번 서버에 있더라"를 일일이 알아야 해서
지저분해진다는 점입니다.

Vitess는 애플리케이션과 여러 대의 MySQL 사이에 끼어들어서, 앱은 그냥 MySQL 한 대에
접속하는 것처럼 쓰게 해주고 뒤에서 실제로 어느 MySQL로 쿼리를 보낼지는 알아서 처리해주는
미들웨어입니다. 원래 유튜브에서 만들었고, 지금은 슬랙, 깃허브, 스퀘어 같은 곳에서도 씁니다.

---

## 2. Vitess를 이루는 요소들

Vitess는 하나의 프로그램이 아니라 역할이 다른 여러 프로세스의 조합입니다. 쉬운 비유로
정리하면 다음과 같습니다.

| 구성요소 | 비유 | 하는 일 |
|---|---|---|
| etcd | 클러스터의 주소록 | "어느 keyspace/shard에 어떤 MySQL이 있고 누가 지금 primary인지"를 저장하는 저장소입니다. Vitess 전용은 아니고, 범용 분산 키값 저장소를 그대로 씁니다. |
| vtctld | 관리자 창구 | 클러스터를 조작하는 관리 API 서버입니다. `vtctldclient`라는 CLI로 이 창구에 명령을 보냅니다(keyspace 생성, 승격, 스키마 적용 등). |
| vttablet | MySQL 한 대를 담당하는 비서 | MySQL 인스턴스 하나당 반드시 하나씩 붙습니다. 쿼리를 실제 MySQL로 전달하고, 헬스체크 결과를 클러스터에 보고하며, 모드에 따라 MySQL 프로세스 자체를 관리하기도 합니다. |
| vtgate | 안내 데스크 | 앱이 실제로 접속하는 곳입니다. MySQL 프로토콜을 그대로 흉내내서 일반 MySQL 클라이언트로 접속할 수 있습니다. 어느 shard로 쿼리를 보내야 할지 판단해서 알맞은 vttablet에 전달합니다. 상태가 없어서(stateless) 몇 대를 띄우든 동일하게 동작하고, 그 덕분에 로드밸런싱과 이중화가 자연스럽게 됩니다. |

vttablet은 "MySQL 개수"에 비례해서 늘어나고, vtgate는 "요청 처리량"에 비례해서 늘어납니다.
둘 다 "서버 여러 대"라서 같은 걸로 착각하기 쉬운데, 늘어나는 이유는 완전히 다릅니다.

---

## 3. 토폴로지, 뭐가 다른가요

Vitess로 클러스터를 짤 때 결정해야 할 축이 크게 세 가지 있습니다.

### 3-1. Managed vs Unmanaged: MySQL을 누가 기동/제어하나

| | Unmanaged | Managed |
|---|---|---|
| MySQL은 누가 띄우나 | 이미 떠 있는 MySQL(사내 서버, RDS, Aurora 등)에 vttablet이 그냥 접속만 합니다 | Vitess(`mysqlctl`)가 MySQL 프로세스 자체를 처음부터 만들고 통제합니다 |
| 복제/장애조치 | 외부(운영팀, 다른 도구, 혹은 RDS 자체 HA)가 담당합니다. Vitess는 "지금 이게 primary다"라는 결과만 통보받습니다 | Vitess가 직접 복제를 설정하고 승격 명령까지 수행합니다 |
| 언제 쓰나 | 이미 관리형 DB를 쓰고 있거나, MySQL 버전/설정을 팀이 독자적으로 통제해야 할 때 | Vitess에게 운영을 온전히 맡기고 싶을 때 |

managed라고 해서 Vitess가 자기 버전의 MySQL을 강제하는 게 아닙니다. `mysqlctl`은 그냥 서버에 이미 설치된(또는 먼저 설치해준) `mysqld`를 기동/제어할
뿐이라, MySQL 버전과 벤더 선택권은 여전히 운영팀에게 있습니다.

### 3-2. Sharded vs Unsharded: 테이블을 쪼개나 마나

- Unsharded: keyspace 하나가 MySQL 데이터베이스 하나입니다. 그냥 이름이 다른 독립적인 DB
  여러 개를 Vitess 뒤에 모아둔 것에 가깝습니다.
- Sharded: keyspace 하나의 테이블 하나를 여러 MySQL에 행 단위로 쪼개서 저장합니다.
  클라이언트는 여전히 테이블 하나로 보고 쿼리하지만, 실제로는 여러 shard에 흩어져 있고
  vtgate가 모아서 보여줍니다.

### 3-3. Hash vs Range vindex: 쪼갤 때 기준을 뭘로 잡나 (sharded일 때만 해당)

| | Hash vindex | Range(Numeric) vindex |
|---|---|---|
| 분배 기준 | 컬럼값을 해시해서 균등 분산 | 컬럼값 그대로(해싱 없음) |
| 쓰기 분산 | 균등합니다 | auto-increment처럼 순차 증가하는 값이면 최신 shard에 쓰기가 몰릴 수 있습니다 |
| range 조회(`id BETWEEN`) | 모든 shard에 물어봐야 합니다(scatter) | 관련 shard 1~2개만 찍고 끝납니다 |
| 새 구간 추가 | 개념 자체가 없습니다(해시 공간은 이미 전체가 덮여있음) | 마지막(무한대로 열린) shard를 쪼개는 `Reshard` 워크플로우로만 가능합니다 |

---

## 4. 최종 구조: 베어메탈을 고려한 설계

위 세 가지 축을 조합해보며 여러 버전을 만들어봤는데, 처음엔 vttablet 여러 개가 MySQL
컨테이너 몇 개를 나눠 쓰는 구조로 시작했습니다. 로컬 메모리를 아끼려는 편법이었는데,
결국 실제 배포 모습과는 달랐습니다. 진짜 운영에서는 이렇게 구조를 잡아야 하는 이유가
있습니다.

- vttablet과 그 MySQL은 항상 같은 곳에 co-locate해야 합니다. 모든 쿼리가 이 둘 사이를
  지나가니 레이턴시 문제가 있고, MySQL이 죽으면 vttablet도 같이 죽어야 vtgate가 즉시
  알아챌 수 있습니다.
- Kubernetes를 쓴다면 이게 같은 Pod 안의 컨테이너들로 표현되지만, k8s가 꼭 필요한 건
  아닙니다. 베어메탈이나 VM 한 대에 프로세스 여러 개를 그냥 같이 띄우는 것과 원리는
  같습니다.

그래서 최종적으로는 k8s 없이, 컨테이너 하나에 MySQL 한 대와 그 옆의 vttablet이 통째로
들어있는 구조로 정리했습니다.

![아키텍처: mysql 클라이언트 → vtgate 2대 → shard 컨테이너 3개(각각 전용 vttablet+mysqld)](/img/2026/08/architecture.png)

(vtgate와 각 shard의 vttablet은 etcd에 등록/조회하는 방식으로 서로를 찾습니다. 도식에서는
co-location 구조를 강조하려고 etcd/vtctld는 생략했습니다. 자세한 내용은 2번 섹션 참고)

컨테이너 하나(`shard0` 등) 안을 열어보면 실제로 프로세스가 이렇게 같이 떠 있습니다.

```
PID 1  vttablet     (이 shard 담당, 쿼리 받아서 mysqld로 전달)
PID 8  mysqlctld    (mysqld를 기동/제어)
PID 64 mysqld_safe  (mysqlctld가 내부적으로 이걸로 mysqld를 띄움)
PID N  mysqld       (진짜 데이터가 저장되는 곳)
```

컨테이너 경계를 걷어내고 생각하면, 이건 그냥 서버 한 대에 MySQL과 그 관리 프로세스가
같이 떠 있는 평범한 그림입니다. k8s Pod을 흉내낸 게 아니라, 베어메탈에 배포한다고 해도
그대로 유효한 구조입니다.

구성 요약: keyspace 1개(`shard_demo`), hash vindex로 shard 3개(`-55`/`55-aa`/`aa-`)로
분할, shard당 primary 1개(replica 없음, 로컬 테스트용 최소 구성), 앞단에 vtgate 2개입니다.

---

## 5. 직접 해보기

```bash
git clone https://github.com/gywndi/vitess-example.git
cd vitess-example
./scripts/up-sharded.sh
```

`up-sharded.sh`가 하는 일은 이 순서대로입니다. 그냥 "실행하면 끝"이 아니라 왜 이 순서인지가
중요한데, 순서를 바꾸면 실제로 죽습니다.

1. etcd, vtctld부터 기동합니다. 이후 모든 단계가 이 둘을 필요로 하니까요.
2. cell(`zone1`)을 등록합니다. tablet이 자기 위치를 topo에서 찾으려면 cell이 먼저 있어야
   하는데, 이거 없이 tablet부터 띄우면 등록 직후 죽습니다.
3. keyspace(`shard_demo`)를 `--durability-policy=none`으로 만들어둡니다. tablet 기동 시
   자동 생성되도록 놔두면 기본 정책(`semi_sync`)이 걸려서, replica가 없는 이 구성에서는
   나중에 승격이 멈출 수 있습니다.
4. shard0/1/2 컨테이너를 기동합니다. 각자 전용 MySQL을 부트스트랩하고 `REPLICA` 상태로
   topo에 등록됩니다. vttablet은 처음부터 `PRIMARY`로 뜰 수 없거든요.
5. 각 tablet을 `PlannedReparentShard`로 `PRIMARY`로 승격합니다. 이 시점부터 실제로 쓰기가
   가능해지고, `vt_shard_demo` 데이터베이스도 자동으로 생깁니다.
6. 스키마와 vschema를 적용합니다. `test_table`을 만들고, id 컬럼을 해시해서 shard를
   정하라는 라우팅 규칙을 등록합니다.
7. vtgate 2대는 반드시 제일 마지막에 띄웁니다. vtgate는 뜰 때 keyspace의 shard 구성을
   한 번에 훑어보는데, 이 상태가 불완전하면(shard가 덜 모였거나 primary가 없으면) fatal로
   죽습니다.

몇 분 뒤 클러스터가 뜨면 다음과 같이 접속할 수 있습니다.

```bash
mysql -h127.0.0.1 -P15306 -uroot shard_demo   # vtgate1
mysql -h127.0.0.1 -P15307 -uroot shard_demo   # vtgate2
```

```sql
INSERT INTO test_table (id, msg) VALUES
 (1,'a'),(2,'b'),(3,'c'),(4,'d'),(5,'e'),(6,'f'),(7,'g'),(8,'h'),(9,'i'),(10,'j');

SELECT * FROM test_table ORDER BY id;
```
```
id  msg
1   a
2   b
3   c
4   d
5   e
6   f
7   g
8   h
9   i
10  j
```
vtgate로 조회하면 10건이 이렇게 하나로 합쳐져서 보입니다. 정말로 물리적으로 3개 MySQL에
나뉘어 저장된 게 맞는지, shard 컨테이너 3개의 전용 mysqld에 각각 직접 붙어서 확인해보면:

```bash
docker exec vitess-shard0 mysql -S /vt/vtdataroot/vt_0000000100/mysql.sock -uvt_dba vt_shard_demo -e "SELECT * FROM test_table ORDER BY id;"
docker exec vitess-shard1 mysql -S /vt/vtdataroot/vt_0000000101/mysql.sock -uvt_dba vt_shard_demo -e "SELECT * FROM test_table ORDER BY id;"
docker exec vitess-shard2 mysql -S /vt/vtdataroot/vt_0000000102/mysql.sock -uvt_dba vt_shard_demo -e "SELECT * FROM test_table ORDER BY id;"
```
```
-- shard0
id  msg
1   a
2   b
3   c

-- shard1
id  msg
5   e
9   i
10  j

-- shard2
id  msg
4   d
6   f
7   g
8   h
```
3 + 3 + 4 = 10건, 정확히 나뉘어 저장되어 있습니다.

정리는 다음 명령으로 합니다.
```bash
docker compose -f docker-compose.sharded.yml down -v
```

---

## 6. 참고: Apache ShardingSphere와 간단히 비교하면

DB 샤딩 미들웨어를 찾다 보면 자연스럽게 비교 대상에 오르는 게 ShardingSphere입니다.
직접 띄워서 비교 테스트한 건 아니고, 문서 기준으로 큰 차이 두 가지만 짚어봅니다.

| | Vitess | ShardingSphere |
|---|---|---|
| 동작 방식 | 항상 프록시(vtgate)를 거칩니다. 이 글에서 계속 본 구조죠 | 선택할 수 있습니다. 프록시 없이 애플리케이션에 JDBC 드라이버로 내장하거나(ShardingSphere-JDBC), Vitess처럼 독립 프록시로 띄울 수도 있습니다(ShardingSphere-Proxy) |
| 지원 DB | MySQL(및 호환 프로토콜)만 | MySQL, PostgreSQL, openGauss 등 여러 RDBMS |
| 라우팅 원리 | SQL을 파싱해서 vindex 규칙으로 shard를 정합니다 | 마찬가지로 SQL을 파싱해서 샤딩 규칙으로 라우팅합니다. 기본 개념은 같습니다 |

실질적으로 가장 크게 갈리는 지점은 "프록시가 있냐 없냐"보다 "프록시 없이 쓸 수 있는
선택지가 있냐"입니다. Vitess는 vtgate라는 네트워크 홉이 구조적으로 항상 필수인 반면,
ShardingSphere는 JDBC 모드를 쓰면 그 홉 자체를 없앨 수 있습니다. 대신 라우팅 로직이
애플리케이션 프로세스 안으로 들어오죠. Vitess는 MySQL 생태계에 집중해서 만들어진 반면
ShardingSphere는 처음부터 여러 RDBMS를 겨냥해서 설계됐다는 점도 실무에서 고를 때 꽤
크게 작용할 만한 차이입니다.
