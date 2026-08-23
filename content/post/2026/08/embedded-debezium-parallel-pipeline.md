---
title: Debezium은 캡처까지만 한다 - 소스 교체와 병렬 처리, 실전에서 확인하기
subtitle: 
author: admin
type: post
date: 2026-08-23T22:30:49+09:00
url: 2026/08/embedded-debezium-parallel-pipeline
categories:
  - CDC
tags:
  - debezium
  - CDC
---

## 이전 글 요약

[이전 글](/2026/08/debezium-smt-cant-parallelize/)에서 확인한 건, Debezium 임베디드 엔진의 콜백을 제출 스레드(TRD1)와 순서 보장 배출 스레드(TRD2)로 나누면 병렬로 처리해도 성능 손실 없이(98~101%) 순서를 지킬 수 있다는 것이었습니다. 다만 그건 id 하나 뽑아서 큐에 넣고 순서만 재본 순수 벤치마크였습니다.

이번 글에서 구현한 건 두 가지입니다.

1. **MySQL을 Postgres로 갈아 끼워도, 우리 코드는 한 줄도 안 바뀔까?** JDBC 드라이버를 바꿔도 애플리케이션 로직은 그대로이듯, Debezium도 "어디서 캡처할지"만 책임지고 그 뒤(가공, 전송)는 전부 우리가 용도에 맞게 짜는 애플리케이션 코드가 되도록 구현했습니다.
2. **워커 4개가 동시에 갈아엎어도, Kafka엔 여전히 1, 2, 3 순서로 꽂힐까?** 지난번엔 id 하나만 뽑아 순서를 쟀지만, 이번엔 진짜 컬럼을 가공하고 진짜 Kafka로 전송하는 작은 애플리케이션으로 그 결론을 그대로 재현했습니다.

## 전체 데이터 흐름

멀티소스는 Debezium 커넥터 단계에서만 갈립니다. 그 뒤(TRD1 - 워커 풀 - TRD2 - KafkaSink)는 소스와 무관하게 완전히 같은 코드가 처리하고, 같은 토픽으로 모입니다.

{{< mermaid >}}
flowchart LR
    M[(MySQL)] --> DBZ
    P[(Postgres)] --> DBZ

    subgraph APP["애플리케이션 (하나의 JVM 프로세스)"]
        DBZ["Debezium 커넥터"] --> PIPE["병렬 transform + 순서 보장 배출<br/>(TRD1 -> 워커 풀 -> TRD2)"]
        PIPE --> SINK["KafkaSink"]
    end

    SINK --> TOPIC[("Kafka<br/>(demo-items-unified)")]

    style APP fill:#F9FAFB,stroke:#8DA3AF,stroke-width:1px
    style DBZ fill:#EAF4FF,stroke:#008AFF,stroke-width:2px
    style PIPE fill:#E6FCF5,stroke:#38D9A9,stroke-width:2px
    style SINK fill:#EAF4FF,stroke:#008AFF,stroke-width:2px
{{< /mermaid >}}

정확히는 Debezium 커넥터와 그 뒤 파이프라인(TRD1/워커 풀/TRD2)은 소스마다 별도 인스턴스로 떠 있습니다(순서 보장은 소스 안에서만 의미 있으니까요) - 다만 코드는 완전히 동일한 클래스(`ParallelPipeline`)이고, transform 체인과 KafkaSink는 인스턴스 자체를 공유합니다. 그래서 위 그림처럼 "하나의 파이프라인"으로 그려도 실제 동작과 어긋나지 않습니다.

## 확인 1: Debezium은 드라이버, 나머지는 우리 애플리케이션

파이프라인 구조는 `source(Debezium) -> transform 체인 -> sink(Kafka)` 세 단계입니다. Debezium이 맡는 역할은 딱 첫 단계 - 소스에 접속해서 변경 이벤트를 캡처하는 것까지입니다. 그 뒤(어떻게 가공할지, 어디로 보낼지)는 Debezium이 전혀 관여하지 않는 순수 애플리케이션 로직입니다. 이 경계가 확실하면, 소스를 바꾸는 건 **드라이버를 갈아 끼우는 것**과 같아집니다 - 설정 파일 하나만 바꾸면 됩니다.

```yaml
source:
  label: mysql
  connector:
    connector.class: io.debezium.connector.mysql.MySqlConnector   # Postgres면 이 클래스만 다름
    database.hostname: 127.0.0.1
    ...

partitionKey: id                   # 이 값도 소스가 뭐든 완전히 동일

transforms:                        # 이 리스트는 소스가 뭐든 완전히 동일
  - class: net.gywn.debezium.demo.embedded.UppercaseNameTransform
  - class: net.gywn.debezium.demo.embedded.AppendSuffixTransform
    properties:
      suffix: "-verified"

sink:                              # 이 블록도 소스가 뭐든 완전히 동일
  kafka:
    bootstrap.servers: localhost:19092
    topics:                        # 테이블명 -> 토픽 오버라이드. 안 적으면 Debezium 기본 토픽명 그대로
      demo_items: demo-items-unified
```

MySQL용 파일과 Postgres용 파일에서 다른 건 `source` 블록(어느 DB에 어떻게 접속할지)뿐입니다. `partitionKey`/`transforms`/`sink`는 두 파일에서 완전히 같아야 하고, 다르면 실행할 때 경고가 뜹니다 - "소스만 바뀌고 나머지는 안 바뀐다"는 걸 설정 구조 자체가 강제하는 셈입니다.

`sink.kafka.topics`는 짧은 테이블명을 원하는 토픽으로 매핑하는 오버라이드 테이블입니다. 여기 없는 테이블은 Debezium이 기본으로 붙이는 `topic.prefix` + DB + 테이블 이름 규칙을 그대로 씁니다. 두 설정 파일 모두 `demo_items`를 `demo-items-unified`로 매핑해뒀기 때문에, 뒤에서 볼 것처럼 MySQL과 Postgres에서 온 이벤트가 같은 토픽에 함께 쌓입니다.

여기서 바뀌는 건 결국 `connector.class` 한 줄입니다. Debezium은 MySQL, Postgres 외에도 MongoDB, SQL Server 등 여러 소스를 같은 방식(커넥터 클래스 + 표준 설정 프로퍼티)으로 지원합니다 - 즉 이 구조는 두 소스에만 한정되지 않고, Debezium이 지원하는 소스라면 **그대로 확장**됩니다. Debezium을 "MySQL 전용 도구"가 아니라 "소스 갈아 끼우는 범용 CDC 드라이버"로 쓰고, 그 위에 우리 용도에 맞는 파이프라인을 얹은 셈입니다.

## 확인 2: 병렬 처리 + 순서 보장이 실전에서도 통하는가

구조는 이전 글과 같습니다. 다른 점은 큐에 오가는 게 id 하나가 아니라 **실제로 transform을 거친 결과물**이라는 것뿐입니다. 그리고 TRD1(제출 스레드)이 하는 일이 하나 더 늘었습니다 - Kafka 메시지 키(파티션 키)를 정하는 것.

```java
// TRD1 - Debezium 콜백 스레드. 절대 병렬화할 수 없으니 여기서 하는 일은 가벼운 필드
// 조회 하나뿐이어야 한다. 실제 가공(transform)은 전부 워커 풀로 미룬다.
public void submit(SourceRecord record) {
    String partitionKey = resolvePartitionKey(record); // 설정된 컬럼값, 없으면 "db.table"
    Future<Delivery> future = workers.submit(() -> process(record, partitionKey));
    queue.put(future);
}

// 워커 풀 - 여러 스레드가 동시에 이 메서드를 실행한다 (병렬로 도는 부분)
private Delivery process(SourceRecord record, String partitionKey) {
    Struct transformed = ...;                 // Debezium이 캡처한 원본 row
    for (RecordTransform step : transforms) { // 설정에 적힌 순서대로 가공
        transformed = step.apply(transformed);
    }
    return new Delivery(partitionKey, ...);   // 가공 끝난 결과 + 키
}

// 전담 배출 스레드 - 여기서만, 제출한 순서 그대로 Kafka로 보낸다
private void drainLoop() {
    ...
    sink.send(delivery...);
}
```

파티션 키를 왜 TRD1에서 정하냐면, TRD1은 어차피 절대 병렬화할 수 없는 스레드라서 - 여기서 하는 일을 최소한("이 행이 어디로 분산돼야 하는가" 하나만 결정)으로 묶어두고, 나머지 무거운 작업(가공)은 전부 워커 풀로 넘기는 게 맞기 때문입니다. 설정에 지정한 컬럼(`partitionKey`)이 없는 테이블은 `db.테이블명`으로 대신 묶습니다 - 서로 다른 DB의 같은 이름 테이블이 우연히 같은 키로 섞이지 않도록.

MySQL과 Postgres 양쪽에 같은 데이터 15건씩 넣고, 위 `sink.kafka.topics` 설정대로 같은 토픽(`demo-items-unified`)에 모이는지 확인했습니다.

```
1 | {"id":1,"name":"ITEM-1-verified","amount":"1.50"}
2 | {"id":2,"name":"ITEM-2-verified","amount":"3.00"}
3 | {"id":3,"name":"ITEM-3-verified","amount":"4.50"}
1 | {"id":1,"name":"ITEM-1-verified","amount":"1.50"}   <- 여기부터 postgres
2 | {"id":2,"name":"ITEM-2-verified","amount":"3.00"}
...
```

(`키 | 값` 형태로 찍었습니다. 키가 정확히 `id` 값과 같습니다 - 설정한 컬럼이 그대로 Kafka 메시지 키로 들어갔다는 뜻입니다.)

두 소스가 한 토픽에 섞여 들어왔지만, **각 소스 안에서는 id가 항상 1, 2, 3 순서로만 등장**합니다 - 워커 4개가 동시에 가공했는데도 순서가 안 깨진 겁니다. 결과 모양(`ITEM-1-verified` 같은 가공 결과)도 소스에 상관없이 완전히 똑같습니다 - 같은 드라이버 위에서 같은 애플리케이션 코드가 돌았으니 당연한 결과지만, 실제로 확인이 필요했습니다.

## 테스트 방법

```bash
docker-compose up -d             # mysql, postgres, kafka 전부 필요
./scripts/embedded-demo.sh 15    # 스키마 생성 -> 파이프라인 기동 -> 양쪽에 15건씩 주입 -> 결과 확인
```

## 정리

- **Debezium = 범용 CDC 드라이버**. 소스에 접속해서 변경 이벤트를 캡처하는 것까지만 책임지고, 그 이후(가공, 전송)는 관여하지 않는다. 그래서 소스를 바꾸는 일이 설정 파일 하나(`connector.class` 한 줄) 바꾸는 일로 끝난다 - Debezium이 지원하는 어떤 소스로도 확장 가능하다는 뜻이다.
- **우리는 그 위에 용도에 맞는 구조를 만든다**. transform 체인과 sink는 Debezium을 전혀 모르는 애플리케이션 코드이고, 소스가 뭐든 완전히 동일하게 동작한다. 파티션 키 결정(TRD1의 유일한 일)도 마찬가지로 소스 무관하게 동일한 설정 하나로 동작한다.
- **벤치마크 결론은 실전에서도 통한다**. id 하나가 아니라 실제 가공 + 실제 Kafka 전송으로 바꿔도, 병렬로 처리하면서 순서를 지키는 구조는 그대로 성립했다.

Debezium이 공식 지원하는 소스는 MySQL, PostgreSQL, MongoDB, Oracle, SQL Server 등 총 12종([전체 목록](https://debezium.io/documentation/reference/stable/connectors/index.html))입니다. 즉, 지금 당장이라도 다양한 데이터소스 처리가 가능한 이야기지요. 단, Oracle의 경우 OGG(GoldenGate)를 권고하기에 Debezium Oracle 커넥터와는 다른 구현이 필요합니다.

전체 코드는 [debezium-lessons-learned 저장소](https://github.com/gywndi/debezium-lessons-learned)에 있습니다.
