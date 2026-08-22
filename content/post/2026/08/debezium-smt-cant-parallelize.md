---
title: SMT는 병렬화할 수 없다 — Debezium 바깥에서 순서를 지키며 처리량 올리기
subtitle: 
author: admin
type: post
date: 2026-08-18T22:57:37+09:00
url: 2026/08/debezium-smt-cant-parallelize
categories:
  - IT
tags:
  - CDC
  - IT
  - debezium
---

# CDC와 Debezium

서로 다른 종류의 시스템(RDBMS, 검색엔진, 캐시, 다른 서비스의 데이터베이스 등) 간에 데이터를 실시간으로 동기화해야 하는 경우, 원본 데이터베이스를 주기적으로 폴링하는 방식은 확장성과 지연 시간 모두에서 한계가 있습니다. 이 문제를 해결하는 표준적인 방법이 CDC(Change Data Capture)입니다 — 데이터베이스가 남기는 변경 로그를 실시간으로 읽어, 변경 사항을 이벤트로 만들어 필요한 곳에 전달하는 방식입니다. Debezium은 이 CDC를 구현하는 오픈소스 도구 중 가장 널리 쓰이는 것 중 하나이고, 이기종 시스템 간 데이터 동기화 파이프라인의 핵심 구성 요소로 많이 채택되고 있습니다.

Debezium이 널리 쓰이는 이유 중 하나는 MySQL, PostgreSQL, MongoDB 등 다양한 데이터베이스용 커넥터를 동일한 API로 제공한다는 점입니다. 이번 실험에서는 그중 MySQL 커넥터를 썼지만, 여기서 다루는 내용(콜백 처리, SMT 구조, 순서 보장)은 특정 커넥터에 종속되지 않고 임베디드 엔진 전반에 적용됩니다.

# 원래 목표: Transform을 병렬로

처음 세운 목표는 단순했습니다. **Kafka Connect의 Transform(SMT, Single Message Transform) 처리를 병렬로 돌리되, 결과는 원본 binlog 순서를 그대로 유지한다.** 레코드 하나하나에 무거운 변형 작업이 붙는 상황을 가정하고, 병렬화와 순서 보장을 동시에 만족시킬 수 있는지 확인해보려 했습니다.

그런데 조사를 하다 막혔습니다. Kafka Connect의 SMT는 애초에 병렬화할 수 있는 구조가 아니었습니다.

# 막다른 길: SMT는 왜 병렬화가 안 되나

바이트코드를 직접 뜯어서 확인한 사실 세 가지입니다.

1. **`Transformation<R>.apply(R): R`는 설계상 동기(sync) API입니다.** 값을 반환해야만 다음 단계로 넘어가는 구조라, "일단 제출만 해두고 나중에 결과를 회수"하는 방식 자체가 불가능합니다.
2. **`TransformationChain.apply()`는 SMT 체인을 그냥 순서대로 도는 단순 반복문**이고, `AbstractWorkerSourceTask`가 이걸 태스크 스레드 딱 하나에서 인라인으로 호출합니다. 워커 스레드를 늘릴 여지가 없습니다.
3. **MySQL/binlog 계열 커넥터는 태스크를 1개 이상 띄울 수 없습니다.** `BinlogConnector.taskConfigs(int)`는 `tasks.max`가 1보다 크면 그 자리에서 `IllegalArgumentException`을 던집니다. Debezium이 공식으로 제공하는 유일한 병렬 처리 옵션인 `snapshot.max.threads`도 초기 스냅샷 단계에만 적용되고, 스트리밍·Transform 구간과는 무관합니다.

결론은 명확했습니다. **Kafka Connect SMT 체인 안에서는 애초에 병렬화할 방법이 없습니다.** 병렬화하려면 SMT 안이 아니라, SMT 바깥 — 즉 우리가 직접 통제할 수 있는 애플리케이션 레이어에서 해야 합니다.

# 그래서 목표를 바꿨습니다

SMT를 병렬화하는 대신, 다음 세 가지를 같은 조건(같은 binlog 시작 위치, 같은 100만 건 UPDATE 워크로드, 컬럼 20개짜리 테이블 하나)에서 측정하기로 했습니다.

| Test | 무엇을 측정하나 |
|---|---|
| 1. Raw binlog 파싱 | Debezium 없이 `mysql-binlog-connector-java`로 binlog를 직접 읽었을 때의 상한선 |
| 2. Debezium 기준선 | Transform 없는 순수 Debezium 임베디드 엔진 — Debezium 자체가 얹는 오버헤드 |
| 3. Debezium → Queue → `future.get()` | SMT가 아니라 애플리케이션 레이어에서, 제출과 순서 보장 배출을 스레드 두 개로 분리했을 때 |

Test 3이 이 실험의 핵심입니다. SMT 체인 안에서는 안 되지만, Debezium 임베디드 엔진의 `notifying()` 콜백은 값을 반환하지 않는 fire-and-forget 방식이라 여기서는 가능합니다.

(참고: JSON 문자열로 변환해서 받으면 이보다 45%가량 느렸습니다 — 그래서 Test 2/3 모두 JSON 없이 Debezium이 만드는 `SourceRecord`/`Struct`를 그대로 씁니다.)

# Test 3의 구조: TRD1(제출) / TRD2(배출) 분리

제출(TRD1)과 배출(TRD2)이 큐 하나로 어떻게 연결되는지 그림으로 정리하면 다음과 같습니다.

{{< mermaid >}}
flowchart LR
    TRD1["TRD1 (제출)"] -->|"① submit"| Pool[["Thread Pool"]]
    TRD1 -->|"② put(future)"| Q[(Queue)]
    Q -->|"③ poll"| TRD2["TRD2 (배출)"]
    Pool -.->|"④ future.get()"| TRD2

    style Q fill:#FFF3E0,stroke:#FFA94D,stroke-width:2px
    style Pool fill:#E6FCF5,stroke:#38D9A9,stroke-width:2px
{{< /mermaid >}}

TRD1은 워커 풀에 작업을 맡기고 `Future`를 큐에 넣기만 합니다 — `future.get()`을 절대 호출하지 않으므로 큐가 가득 찼을 때의 백프레셔 외에는 블로킹하지 않습니다. `future.get()`은 TRD2에서만 호출되는데, 큐에서 **제출 순서 그대로** 꺼내기 때문에 어느 워커가 언제 끝냈는지와 무관하게 순서가 보장됩니다.

```java
// TRD1 — Debezium 콜백 스레드에서만 호출. future.get()을 절대 하지 않는다.
void submit(SourceRecord record) throws InterruptedException {
    Future<Long> future = workerPool.submit(() -> StructId.extract(record));
    queue.put(future); // 큐가 가득 찼을 때만 여기서 대기 (백프레셔)
}

// TRD2 — 전담 배출 스레드. future.get()은 여기서만 호출된다.
private void drainLoop() {
    while (running || !queue.isEmpty()) {
        Future<Long> future = queue.poll(200, TimeUnit.MILLISECONDS);
        if (future == null) continue;
        long id = future.get();
        orderChecker.check(id);
        tracker.increment();
    }
}
```

핵심은 **제출(TRD1)과 순서 보장 배출(TRD2)이 서로 다른 스레드**라는 점입니다. 배출 쪽(또는 그 뒤 다운스트림 전달)이 느려지더라도, TRD1은 큐 용량만큼은 계속 다음 이벤트를 받을 수 있습니다 — Debezium의 수집 속도와 다운스트림 처리 속도가 서로의 발목을 잡지 않습니다.

# 결과

100만 건 처리 기준 TPS(초당 처리 건수). 테이블은 id + 컬럼 20개짜리 `wide_table` 하나로 고정했고, Test 2/3 모두 JSON 없이 `Struct`를 직접 다룹니다.

| Test | TPS | 비고 |
|---|---|---|
| 1. Raw binlog 파싱 | 264,987 | Debezium/Kafka Connect 레이어 전혀 없음 |
| 2. Debezium 기준선 | 155,049 (Test 1 대비 58.5%) | Transform 없음, JSON 미사용 |
| 3. Debezium → Queue → `future.get()` | 153,219 (Test 2 대비 98.8%) | 순서 위반 0건 |

두 가지가 확인됩니다.

**Test 1과 Test 2의 차이가 Debezium 자체의 병목입니다.** binlog를 실제로 파싱하는 `mysql-binlog-connector-java`는 초당 26만 건 이상을 처리하는데, JSON을 전혀 쓰지 않는데도 그 위에 Debezium이 파싱된 row를 자기 내부 이벤트 구조(Struct/Envelope)로 변환하는 과정을 거치면 초당 15만 건대로 떨어집니다. 이건 앞서 걷어낸 JSON 직렬화와는 별개로 남는, Transform 코드로는 줄일 수 없는 순수 프레임워크 오버헤드입니다.

**Test 2와 Test 3의 차이는 사실상 없습니다.** 스레드를 분리하고 그 사이에 블로킹 큐 + `Future`를 끼워 넣어도, 순수 Debezium 대비 성능 손실이 없었습니다(반복 측정에서 98~101% 사이). 순서는 반복 측정 전 구간에서 위반 0건이었습니다(`verify/OrderChecker`). 즉 **"제출과 순서 보장 배출을 분리한다"는 이 구조 자체는 공짜**이고, 병목은 여전히 Debezium 자체(Test 1 vs 2 구간)에 있다는 뜻입니다.

# 테스트 방법

전체 파이프라인은 스크립트 4개로 재현할 수 있습니다.

```bash
./scripts/mysql.sh up      # MySQL 컨테이너 기동 (binlog ROW 포맷)
./scripts/seed.sh          # 100만 행 적재, 시작 offset/binlog 위치 캡처, UPDATE 워크로드 생성
./scripts/run-test.sh 1    # <1|2|3> — 단일 테스트 실행
./scripts/run-all.sh       # 위 전체 자동 실행: up → seed → 3개 테스트 순차 실행
```

`seed.sh`는 Debezium용 offset 파일과, `mysql-binlog-connector-java`가 직접 사용하는 `file:position` 좌표를 같은 시점에 함께 캡처합니다 — 세 테스트 모두 정확히 같은 시작 위치에서 같은 100만 건짜리 이벤트 스트림을 소비하므로 테스트 간 비교가 공정합니다. 순서 보장 여부는 각 실행이 끝날 때 자동으로 출력됩니다.

# 정리

- SMT(Kafka Connect Transform) 체인은 설계상 싱글 프로세싱입니다 — `apply()`가 동기 API이고, MySQL/binlog 커넥터는 태스크 1개로 고정되어 있어 병렬화할 여지가 없습니다. 이건 바이트코드로 직접 확인한 사실입니다.
- 그래서 병렬화·디커플링은 SMT 안이 아니라 SMT 바깥, 즉 다운스트림 애플리케이션 코드에서 해야 합니다.
- JSON 변환은 검증해보니 불필요한 오버헤드였습니다(45% 손해). 그래서 이 저장소의 모든 벤치마크는 Debezium의 `SourceRecord`/`Struct`를 그대로 다루고, JSON이 필요하면 마지막 단계에서 병렬로 따로 처리하는 쪽을 택했습니다.
- Debezium 임베디드 엔진의 `notifying()` 콜백에서는 제출(TRD1)과 순서 보장 배출(TRD2)을 스레드 두 개로 분리하는 게 가능하고, 이 구조는 순수 Debezium 대비 성능 손실 없이 순서를 지킵니다.
- 남은 병목은 애플리케이션 레이어가 아니라 Debezium 자체의 connector → 내부 자료구조 변환 구간입니다 — JSON을 걷어낸 뒤에도 남습니다.

Kafka Connect 커넥터(진짜 SMT 체인)로 전환할 때 이 구조를 그대로 가져갈 수 없는 이유와 실제로 무엇이 바뀌어야 하는지는 별도 문서([Kafka Connect 전환 체크리스트](kafka-connect-conversion-notes.md))에 정리했습니다.

전체 코드는 [debezium-lessons-learned 저장소](https://github.com/gywndi/debezium-lessons-learned)에 있습니다.
