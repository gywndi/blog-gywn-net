---
title: Debezium Only Captures - Verifying Source Swapping and Parallel Processing in Practice
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

## Previous Post Recap

In the [previous post](/en/2026/08/debezium-smt-cant-parallelize/), I confirmed that splitting the Debezium embedded engine's callback into a submit thread (TRD1) and an order-preserving drain thread (TRD2) lets you process in parallel with no performance loss (98-101%) while still preserving order. But that was a pure benchmark - just a single id pulled out, queued, and checked for order.

This post set out to build two things.

1. **Can you swap MySQL for Postgres without changing a single line of our code?** Just as swapping a JDBC driver leaves the application logic untouched, I implemented Debezium so it's only responsible for "where to capture from" - everything after that (transforming, sending) is application code we write however we need.
2. **Does "parallel processing while preserving order," confirmed by the benchmark, still hold when the workers are running a real transform and sending to a real Kafka, not just an id?** Last time I measured order with a single id; this time I reproduced that same conclusion with a small application that transforms real columns and sends to a real Kafka.

## The Full Data Flow

Multi-source only branches at the Debezium connector stage. Everything after that (TRD1 - worker pool - TRD2 - KafkaSink) is handled by exactly the same code regardless of source, and it all lands in the same topic.

{{< mermaid >}}
flowchart LR
    M[(MySQL)] --> DBZ
    P[(Postgres)] --> DBZ

    subgraph APP["Application (single JVM process)"]
        DBZ["Debezium connector"] --> PIPE["Parallel transform + order-preserving drain<br/>(TRD1 -> worker pool -> TRD2)"]
        PIPE --> SINK["KafkaSink"]
    end

    SINK --> TOPIC[("Kafka<br/>(demo-items-unified)")]

    style APP fill:#F9FAFB,stroke:#8DA3AF,stroke-width:1px
    style DBZ fill:#EAF4FF,stroke:#008AFF,stroke-width:2px
    style PIPE fill:#E6FCF5,stroke:#38D9A9,stroke-width:2px
    style SINK fill:#EAF4FF,stroke:#008AFF,stroke-width:2px
{{< /mermaid >}}

To be precise, the Debezium connector and the pipeline behind it (TRD1/worker pool/TRD2) run as separate instances per source (order guarantees only make sense within a single source). But the code is exactly the same class (`ParallelPipeline`), and the transform chain and KafkaSink share the same instances. So drawing it as "one pipeline" above doesn't misrepresent what actually happens.

## Verification 1: Debezium Is a Driver, Everything Else Is Our Application

The pipeline structure is three stages: `source(Debezium) -> transform chain -> sink(Kafka)`. Debezium's job is exactly the first stage - connecting to a source and capturing change events. Everything after that (how to transform, where to send) is pure application logic that Debezium has nothing to do with. Once this boundary is fixed, swapping sources becomes **swapping a driver** - just change one config file.

```yaml
source:
  label: mysql
  connector:
    connector.class: io.debezium.connector.mysql.MySqlConnector   # Only this class differs for Postgres
    database.hostname: 127.0.0.1
    ...

partitionKey: id                   # Identical regardless of source

transforms:                        # This list is identical regardless of source
  - class: net.gywn.debezium.demo.embedded.UppercaseNameTransform
  - class: net.gywn.debezium.demo.embedded.AppendSuffixTransform
    properties:
      suffix: "-verified"

sink:                              # This block is identical regardless of source
  kafka:
    bootstrap.servers: localhost:19092
    topics:                        # table name -> topic override. Falls back to Debezium's default topic name if omitted
      demo_items: demo-items-unified
```

The only difference between the MySQL config file and the Postgres one is the `source` block (which DB, how to connect). `partitionKey`/`transforms`/`sink` must be identical across both files, and a warning fires at startup if they're not - the config structure itself enforces "only the source changes, nothing else does."

`sink.kafka.topics` is an override table mapping a short table name to whatever topic you want. Any table not listed here keeps Debezium's default `topic.prefix` + DB + table naming. Both config files map `demo_items` to `demo-items-unified`, which is why, as you'll see below, events from both MySQL and Postgres end up piling into the same topic.

In the end, the only thing that changes is one line, `connector.class`. Debezium supports MySQL, Postgres, and several other sources like MongoDB and SQL Server the same way (connector class + standard config properties) - so this structure isn't limited to two sources; it **extends as-is** to whatever source Debezium supports. Debezium stops being a "MySQL-only tool" and becomes a general-purpose CDC driver you swap sources on, with our own pipeline built on top for whatever we need it for.

## Verification 2: Does Parallel Processing + Order Preservation Hold Up in Practice?

The structure is the same as the previous post. The only difference is that what flows through the queue isn't a single id but **the actual output of the transform chain**. And TRD1 (the submit thread) now has one more job: deciding the Kafka message key (the partition key).

```java
// TRD1 - the Debezium callback thread. Can never be parallelized, so the only thing done
// here should be a cheap field lookup. All the actual work (transform) is deferred to the worker pool.
public void submit(SourceRecord record) {
    String partitionKey = resolvePartitionKey(record); // configured column's value, or "db.table" if absent
    Future<Delivery> future = workers.submit(() -> process(record, partitionKey));
    queue.put(future);
}

// Worker pool - multiple threads run this method concurrently (this is the parallel part)
private Delivery process(SourceRecord record, String partitionKey) {
    Struct transformed = ...;                 // the raw row Debezium captured
    for (RecordTransform step : transforms) { // applied in the order configured
        transformed = step.apply(transformed);
    }
    return new Delivery(partitionKey, ...);   // the transformed result + key
}

// Dedicated drain thread - only here, sent to Kafka in exact submit order
private void drainLoop() {
    ...
    sink.send(delivery...);
}
```

Why decide the partition key on TRD1? Because TRD1 can never be parallelized anyway - so it makes sense to keep its job to a bare minimum (deciding just one thing: "where should this row be distributed to") and push everything heavy (the transform) onto the worker pool. A table with no configured column (`partitionKey`) groups under `db.tablename` instead - so that two same-named tables from different databases don't accidentally collide on the same key.

I loaded 15 identical rows into both MySQL and Postgres and checked whether they landed in the same topic (`demo-items-unified`) per the `sink.kafka.topics` setting above.

```
1 | {"id":1,"name":"ITEM-1-verified","amount":"1.50"}
2 | {"id":2,"name":"ITEM-2-verified","amount":"3.00"}
3 | {"id":3,"name":"ITEM-3-verified","amount":"4.50"}
1 | {"id":1,"name":"ITEM-1-verified","amount":"1.50"}   <- postgres starts here
2 | {"id":2,"name":"ITEM-2-verified","amount":"3.00"}
...
```

(Printed as `key | value`. The key matches the `id` value exactly - meaning the configured column made it straight into the Kafka message key.)

The two sources ended up mixed in the same topic, but **within each source, ids always show up in strict 1, 2, 3 order** - order held even though 4 workers were transforming concurrently. The shape of the result (transformed output like `ITEM-1-verified`) is also identical regardless of source - an expected outcome since the same application code ran on top of the same driver, but one that still needed to be checked.

## How to Test

```bash
docker-compose up -d             # needs mysql, postgres, and kafka all running
./scripts/embedded-demo.sh 15    # create schema -> start pipeline -> insert 15 rows into both -> check results
```

## Summary

- **Debezium = general-purpose CDC driver.** It's responsible only for connecting to a source and capturing change events; it has nothing to do with what happens after (transform, delivery). So swapping sources ends with changing one line in a config file (`connector.class`) - meaning it extends to any source Debezium supports.
- **We build the structure we need on top of it.** The transform chain and sink are application code that knows nothing about Debezium, and they behave identically no matter the source. Deciding the partition key (TRD1's only job) also runs off a single source-agnostic config, the same way.
- **The benchmark's conclusion holds up in practice.** Swap a single id for real transforms plus real Kafka delivery, and the structure that processes in parallel while preserving order still stands.

Debezium officially supports MySQL, PostgreSQL, MongoDB, Oracle, SQL Server, and more - 12 sources in total ([full list](https://debezium.io/documentation/reference/stable/connectors/index.html)). In other words, a wide range of data sources is already within reach today. One exception: Oracle recommends OGG (GoldenGate), so it needs a different implementation from the standard Debezium Oracle connector.

The full code is in the [debezium-lessons-learned repository](https://github.com/gywndi/debezium-lessons-learned).
