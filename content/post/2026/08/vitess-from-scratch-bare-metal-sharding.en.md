---
title: Understanding Vitess by Building It Yourself, Locally
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

There comes a point where a single MySQL instance just can't keep up with the data anymore.
Vitess is one of the approaches YouTube, Slack, and GitHub have used to solve this problem.
I worked through what Vitess actually does, what components it's made of, and how those
components should actually be laid out, by building it myself in a local Docker environment.
The setup shown here is posted as-is in a [GitHub repo](https://github.com/gywndi/vitess-example),
and you can spin it up yourself with nothing but Docker.

---

## 1. What is Vitess?

There's a point where a single MySQL instance either holds too much data or takes too much
write traffic. The common fix is sharding — splitting the data across multiple MySQL instances.
The problem is that when you shard it yourself, your application code has to know exactly
"which server holds this piece of data," which gets messy fast.

Vitess sits between your application and a fleet of MySQL instances. The app just connects as
if it were talking to a single MySQL server, and behind the scenes Vitess figures out which
MySQL instance a given query actually needs to go to. It was originally built at YouTube, and
today it's also used at places like Slack, GitHub, and Square.

---

## 2. What Vitess Is Made Of

Vitess isn't a single program — it's a combination of several processes, each with a different
role. Here's a simple analogy for each one:

| Component | Analogy | What it does |
|---|---|---|
| etcd | The cluster's address book | Stores which MySQL lives in which keyspace/shard, and who the current primary is. It's not Vitess-specific — it's just a general-purpose distributed key-value store used as-is. |
| vtctld | The admin desk | An admin API server for operating the cluster. You send it commands through the `vtctldclient` CLI (creating keyspaces, promotions, applying schema, etc.). |
| vttablet | The personal assistant for one MySQL instance | Exactly one per MySQL instance. It forwards queries to the actual MySQL, reports health-check results to the cluster, and — depending on mode — can also manage the MySQL process itself. |
| vtgate | The front desk | This is what the app actually connects to. It mimics the MySQL protocol closely enough that a normal MySQL client can connect to it directly. It figures out which shard a query needs to go to and forwards it to the right vttablet. It's stateless, so you can run any number of instances and they all behave identically — which naturally gives you load balancing and redundancy. |

vttablet scales with "how many MySQL instances you have," while vtgate scales with "how much
request throughput you need." Both look like "a bunch of servers," so it's easy to conflate
them, but the reason each one scales is completely different.

---

## 3. What Makes Topologies Different

There are broadly three axes you need to decide on when laying out a Vitess cluster.

### 3-1. Managed vs. Unmanaged: Who Starts and Controls MySQL

| | Unmanaged | Managed |
|---|---|---|
| Who starts MySQL | vttablet simply connects to a MySQL that's already running (an in-house server, RDS, Aurora, etc.) | Vitess (`mysqlctl`) creates and controls the MySQL process itself, from scratch |
| Replication / failover | Handled externally (an ops team, another tool, or RDS's own HA). Vitess is only ever told "this one is primary now" | Vitess sets up replication itself and even performs the promotion |
| When to use it | When you're already on a managed DB, or your team needs independent control over MySQL version/config | When you want to hand operations over to Vitess entirely |

"Managed" doesn't mean Vitess forces its own MySQL version on you. `mysqlctl` just starts and
controls an existing (or pre-installed) `mysqld` on the server — the choice of MySQL version
and vendor still belongs to the ops team.

### 3-2. Sharded vs. Unsharded: Do You Split Tables or Not

- Unsharded: one keyspace equals one MySQL database. It's closer to a set of independent,
  differently-named databases gathered behind Vitess.
- Sharded: a single table in a keyspace is split by row across multiple MySQL instances.
  Clients still query it as if it were one table, but it's actually scattered across several
  shards, and vtgate stitches the results back together.

### 3-3. Hash vs. Range Vindex: What Do You Split On (Sharded Only)

| | Hash vindex | Range (Numeric) vindex |
|---|---|---|
| Distribution basis | Hashes the column value for even distribution | Uses the column value as-is (no hashing) |
| Write distribution | Even | If the value increases sequentially (like auto-increment), writes can pile up on the newest shard |
| Range queries (`id BETWEEN`) | Has to ask every shard (scatter) | Only needs to hit one or two relevant shards |
| Adding a new range | No such concept (the hash space is already fully covered) | Only possible via the `Reshard` workflow, splitting the last (open-ended) shard |

---

## 4. The Final Structure: Designed with Bare Metal in Mind

I combined the three axes above into several different versions. I initially started with
multiple vttablets sharing a handful of MySQL containers — a shortcut to save local memory —
but that ended up diverging from what a real deployment actually looks like. There are real
reasons production needs to be structured the way it is.

- A vttablet and its MySQL must always be co-located. Every query passes between the two, so
  there's a latency concern, and if MySQL dies, vttablet needs to die with it so vtgate can
  notice immediately.
- If you're using Kubernetes, this is expressed as containers inside the same Pod, but
  Kubernetes isn't actually required. The same principle applies to running several processes
  together on a single bare-metal box or VM.

So in the end, I settled on a structure with no k8s at all: one container holding a single
MySQL instance and its dedicated vttablet, packaged together as a unit.

![Architecture: mysql client → 2 vtgates → 3 shard containers (each with its own vttablet+mysqld)](/img/2026/08/architecture.png)

(vtgate and each shard's vttablet find each other by registering with and querying etcd. The
diagram omits etcd/vtctld to emphasize the co-location structure — see section 2 for details.)

If you open up a single container (e.g. `shard0`), here's what's actually running together
inside it:

```
PID 1  vttablet     (handles this shard, receives queries and forwards them to mysqld)
PID 8  mysqlctld    (starts/controls mysqld)
PID 64 mysqld_safe  (mysqlctld uses this internally to start mysqld)
PID N  mysqld       (where the actual data lives)
```

Strip away the container boundary and this is just an ordinary picture of a single server
running MySQL alongside its management processes. It's not mimicking a k8s Pod — it's a
structure that holds up just as well if you deploy it on bare metal.

Summary of the setup: one keyspace (`shard_demo`), split into 3 shards (`-55`/`55-aa`/`aa-`)
using a hash vindex, one primary per shard (no replicas — the minimal setup for local testing),
and two vtgates in front.

---

## 5. Try It Yourself

```bash
git clone https://github.com/gywndi/vitess-example.git
cd vitess-example
./scripts/up-sharded.sh
```

Here's the exact order `up-sharded.sh` runs things in. This isn't a "just run it and you're
done" situation — the order actually matters, and things break if you change it.

1. Start etcd and vtctld first, since every step after this depends on both of them.
2. Register the cell (`zone1`). A tablet needs to be able to look up its own location in the
   topo, which requires the cell to exist first — starting a tablet before this exists causes
   it to die immediately after registering.
3. Create the keyspace (`shard_demo`) with `--durability-policy=none`. If you let it get
   auto-created when a tablet starts instead, it gets the default policy (`semi_sync`), which
   can later stall promotion in this replica-less setup.
4. Start the shard0/1/2 containers. Each one bootstraps its own dedicated MySQL and registers
   with the topo as `REPLICA` — a vttablet can never come up as `PRIMARY` from the start.
5. Promote each tablet to `PRIMARY` via `PlannedReparentShard`. From this point on, writes are
   actually possible, and the `vt_shard_demo` database gets created automatically.
6. Apply the schema and vschema. This creates `test_table` and registers the routing rule that
   hashes the id column to decide which shard it belongs to.
7. Start the two vtgates absolutely last. When vtgate comes up, it scans the keyspace's shard
   layout in one pass — if that state is incomplete (missing shards, or no primary yet), it
   dies with a fatal error.

Once the cluster comes up a few minutes later, you can connect like this:

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
Querying through vtgate shows all 10 rows merged into one result, as expected. To confirm
they're really physically split across 3 separate MySQL instances, you can connect directly to
each of the three shard containers' dedicated mysqld:

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
3 + 3 + 4 = 10 rows, split exactly as expected.

To tear it all down:
```bash
docker compose -f docker-compose.sharded.yml down -v
```

---

## 6. A Quick Comparison with Apache ShardingSphere

If you go looking for DB sharding middleware, ShardingSphere naturally comes up as a point of
comparison. I didn't actually spin it up and run a head-to-head test — just noting two big
differences based on the documentation.

| | Vitess | ShardingSphere |
|---|---|---|
| How it operates | Always goes through a proxy (vtgate) — the structure this whole post has been about | You can choose: embed it in the application as a JDBC driver with no proxy (ShardingSphere-JDBC), or run it as a standalone proxy like Vitess (ShardingSphere-Proxy) |
| Supported databases | MySQL only (and MySQL-compatible protocols) | Multiple RDBMS — MySQL, PostgreSQL, openGauss, and more |
| Routing logic | Parses the SQL and decides the shard using vindex rules | Also parses the SQL and routes it using sharding rules — the underlying concept is the same |

The biggest practical difference isn't really "is there a proxy or not" — it's "is there an
option to use it *without* a proxy." With Vitess, the vtgate network hop is structurally always
required, whereas ShardingSphere's JDBC mode lets you eliminate that hop entirely — at the cost
of pulling the routing logic into your application process. Vitess was built with a laser focus
on the MySQL ecosystem, while ShardingSphere was designed from the start to target multiple
RDBMSes — a difference that can matter quite a bit when choosing between them in practice.
