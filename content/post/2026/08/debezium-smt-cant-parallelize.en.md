---
title: SMTs Can't Be Parallelized — Boosting Throughput Outside Debezium While Preserving Order
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

# CDC and Debezium

When you need to sync data in real time between heterogeneous systems (RDBMS, search engines, caches, other services' databases, etc.), periodically polling the source database has limits in both scalability and latency. CDC (Change Data Capture) is the standard way to solve this — reading a database's change log in real time and turning those changes into events delivered to wherever they're needed. Debezium is one of the most widely used open-source tools for implementing CDC, and it's a common core component in data-sync pipelines across heterogeneous systems.

One reason Debezium is so widely adopted is that it exposes the same API across connectors for many different databases — MySQL, PostgreSQL, MongoDB, and more. This experiment uses the MySQL connector, but what's covered here (callback handling, SMT structure, order guarantees) isn't tied to a specific connector — it applies to the embedded engine generally.

# The Original Goal: Parallelize the Transform

The initial goal was simple: **run Kafka Connect's Transform (SMT, Single Message Transform) processing in parallel, while keeping the output in the original binlog order.** Assuming each record carries a heavy transformation, I wanted to check whether parallelism and order guarantees could be satisfied at the same time.

Digging in, I hit a wall. Kafka Connect's SMT was never structured to be parallelizable in the first place.

# Dead End: Why SMTs Can't Be Parallelized

Three facts confirmed by reading the bytecode directly:

1. **`Transformation<R>.apply(R): R` is a synchronous API by design.** It only moves to the next stage once a value is returned, so a "submit now, collect the result later" approach is fundamentally impossible.
2. **`TransformationChain.apply()` is just a plain loop over the SMT chain**, and `AbstractWorkerSourceTask` calls it inline on a single task thread. There's no room to add worker threads.
3. **MySQL/binlog-family connectors can't run more than one task.** `BinlogConnector.taskConfigs(int)` throws an `IllegalArgumentException` immediately if `tasks.max` is greater than 1. Even `snapshot.max.threads` — the only officially supported parallelism knob in Debezium — only applies to the initial snapshot phase and has nothing to do with the streaming/transform path.

The conclusion was clear. **There is no way to parallelize inside the Kafka Connect SMT chain.** If you want parallelism, it has to happen outside the SMT — in the application layer you actually control.

# So I Changed the Goal

Instead of parallelizing the SMT, I decided to measure three things under identical conditions (same binlog start position, same 1M-row UPDATE workload, one table with 20 columns):

| Test | What it measures |
|---|---|
| 1. Raw binlog parsing | The upper bound when reading the binlog directly with `mysql-binlog-connector-java`, no Debezium |
| 2. Debezium baseline | Pure Debezium embedded engine with no Transform — the overhead Debezium itself adds |
| 3. Debezium → Queue → `future.get()` | Not inside the SMT but in the application layer: splitting submission and order-preserving drain across two threads |

Test 3 is the heart of this experiment. It's impossible inside the SMT chain, but Debezium's embedded-engine `notifying()` callback is a fire-and-forget mechanism that doesn't return a value, which makes it possible here.

(Note: converting to a JSON string turned out to be about 45% slower — so both Test 2 and Test 3 work directly with the `SourceRecord`/`Struct` that Debezium produces, without JSON.)

# The Structure of Test 3: Splitting TRD1 (Submit) / TRD2 (Drain)

Here's how submission (TRD1) and drain (TRD2) connect through a single queue.

{{< mermaid >}}
flowchart LR
    TRD1["TRD1 (submit)"] -->|"① submit"| Pool[["Thread Pool"]]
    TRD1 -->|"② put(future)"| Q[(Queue)]
    Q -->|"③ poll"| TRD2["TRD2 (drain)"]
    Pool -.->|"④ future.get()"| TRD2

    style Q fill:#FFF3E0,stroke:#FFA94D,stroke-width:2px
    style Pool fill:#E6FCF5,stroke:#38D9A9,stroke-width:2px
{{< /mermaid >}}

TRD1 only hands work to the worker pool and pushes the `Future` onto the queue — it never calls `future.get()`, so it never blocks except for backpressure when the queue is full. `future.get()` is only ever called on TRD2, and because it pulls from the queue in **exact submission order**, ordering is guaranteed regardless of which worker finishes when.

```java
// TRD1 — called only from the Debezium callback thread. Never calls future.get().
void submit(SourceRecord record) throws InterruptedException {
    Future<Long> future = workerPool.submit(() -> StructId.extract(record));
    queue.put(future); // blocks here only when the queue is full (backpressure)
}

// TRD2 — dedicated drain thread. future.get() is only ever called here.
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

The key point is that **submission (TRD1) and order-preserving drain (TRD2) run on separate threads**. Even if the drain side (or delivery further downstream) slows down, TRD1 can keep accepting new events up to the queue's capacity — Debezium's ingestion rate and downstream processing rate no longer hold each other back.

# Results

TPS (transactions per second) measured over 1M records. The table is fixed as a single `wide_table` with an id plus 20 columns, and both Test 2 and Test 3 work with `Struct` directly, without JSON.

| Test | TPS | Notes |
|---|---|---|
| 1. Raw binlog parsing | 264,987 | No Debezium/Kafka Connect layer at all |
| 2. Debezium baseline | 155,049 (58.5% of Test 1) | No Transform, no JSON |
| 3. Debezium → Queue → `future.get()` | 153,219 (98.8% of Test 2) | Zero order violations |

Two things stand out.

**The gap between Test 1 and Test 2 is Debezium's own bottleneck.** `mysql-binlog-connector-java`, which actually parses the binlog, handles over 260K events per second. Even with JSON removed entirely, once Debezium converts those parsed rows into its internal event structures (Struct/Envelope) on top of that, throughput drops to the 150K range. That's pure framework overhead — separate from the JSON serialization already stripped out — that Transform code can't reduce.

**There's essentially no difference between Test 2 and Test 3.** Splitting the threads and inserting a blocking queue + `Future` between them cost no performance versus pure Debezium (98–101% across repeated runs). Order violations were zero across every run (`verify/OrderChecker`). In other words, **the structure of "separate submission from order-preserving drain" is free**, and the bottleneck still lives inside Debezium itself (the Test 1 vs. 2 gap).

# How to Reproduce

The full pipeline can be reproduced with four scripts:

```bash
./scripts/mysql.sh up      # start the MySQL container (binlog ROW format)
./scripts/seed.sh          # load 1M rows, capture the starting offset/binlog position, generate the UPDATE workload
./scripts/run-test.sh 1    # <1|2|3> — run a single test
./scripts/run-all.sh       # run everything above automatically: up → seed → all 3 tests in sequence
```

`seed.sh` captures both Debezium's offset file and the `file:position` coordinates that `mysql-binlog-connector-java` uses directly, at the same moment — so all three tests consume exactly the same 1M-event stream from the same starting position, making the comparison fair. Whether ordering held is printed automatically at the end of each run.

# Summary

- The SMT (Kafka Connect Transform) chain is single-threaded by design — `apply()` is a synchronous API, and MySQL/binlog connectors are pinned to a single task, leaving no room for parallelism. This is confirmed directly from the bytecode.
- So parallelization and decoupling have to happen outside the SMT, in downstream application code.
- JSON conversion turned out to be unnecessary overhead (a 45% cost) once verified. Every benchmark in this repo works directly with Debezium's `SourceRecord`/`Struct`, and handles JSON separately and in parallel only at the final stage if needed.
- In Debezium's embedded-engine `notifying()` callback, it's possible to split submission (TRD1) and order-preserving drain (TRD2) across two threads, and this structure preserves ordering with no performance loss versus pure Debezium.
- The remaining bottleneck isn't the application layer — it's Debezium's own connector → internal data structure conversion step. It's still there even after removing JSON.

Why this structure can't carry over as-is when switching to a real Kafka Connect connector (an actual SMT chain), and what actually needs to change, is documented separately in the [Kafka Connect conversion checklist](kafka-connect-conversion-notes.md).

The full code is in the [debezium-lessons-learned repository](https://github.com/gywndi/debezium-lessons-learned).
