---
title: Apache Ignite로 분산 캐시 만들어보고 싶어요 (1탄)
author: gywndi
type: post
date: 2023-10-10T07:10:35+00:00
url: 2023/10/apache-ignite-as-cache-cluster
categories:
  - Ignite
  - NoSQL
  - Research
tags:
  - cache
  - gridgain
  - ignite

---
# Overview

안녕하세요. 벌써 일년이 넘는 시간동안 포스팅을 하지 않았네요. 

그동안 업무적으로 많은 변화도 있던 격동의 시기였던지라, 제 삶의 가장 중요한 요소 중 하나라 생각하던 공유의 가치를 그만 간과하고 말았네요. 물론 포스팅을 멈춘 시간동안 놀지 않고 많은 경험을 쌓아보았습니다.

**오늘은 그중 하나, 인메모리 데이터베이스인 Apache Ignite에 대해 이야기를 해보고자 합니다.**

# Apache Ignite?

이미 많은 분들이 Ignite 를 사용해보셨을 수도 있겠습니다만, 저는 DBA로 일을 하면서도 늘 제대로된 캐시 용도로 써보고 싶었던 분산 인메모리 데이터베이스가 Apache Ignite입니다.

![](/img/2023/10/image-1-1024x453.png)

Server 기반 클러스터링 구성도 가능하고, Application 기반 클러스터링도 가능합니다. 참고로, 이 포스팅에서 이야기할 내용은 Server 기반 클러스터링 구성이고, 인메모리가 아닌 파일 기반 분산 캐시 형태로 사용합니다. SSD로 인해 디스크 Random I/O가 과거 대비 압도적으로 향상된만큼, 캐시 데이터 또한 디스크에 저장하지 않을 이유는 없습니다.

저는 개인적으로 하단 세가지 특성을 Ignite의 가장 큰 강점이라 생각합니다.

* **Persistence Mode**
* **SQL(JDBC) 지원**
* **분산 캐시**
* **스케일 인/아웃**

# Quick Start 

도커 기반으로 로컬에서 기능적으로 간단하게 테스트해볼 수 있는 환경을 구성해봅니다.

```bash
## 도커에서 사용한 데이터 영역 마운트를 위해 디렉토리 생성
$ mkdir -p $HOME/ignite/storage

## persistenceEnabled만 들어간 설정을 생성하기
$ echo '<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans
        http://www.springframework.org/schema/beans/spring-beans.xsd">
    <bean id="ignite.cfg" class="org.apache.ignite.configuration.IgniteConfiguration">
        <property name="dataStorageConfiguration">
            <bean class="org.apache.ignite.configuration.DataStorageConfiguration">
                <property name="defaultDataRegionConfiguration">
                    <bean class="org.apache.ignite.configuration.DataRegionConfiguration">
                        <property name="persistenceEnabled" value="true"/>
                    </bean>
                </property>
            </bean>
        </property>
    </bean>
</beans>' > $HOME/ignite/storage/config.xml

## 도커 시작
$ docker run -d                        \
  -p "10800:10800"                   \
  -v $HOME/ignite/storage:/storage   \
  -e IGNITE_WORK_DIR=/storage        \
  -e CONFIG_URI=/storage/config.xml  \
  --name ignite                      \
  apacheignite/ignite

## 클러스터를 ACTIVE로 전환
$ docker exec ignite bash -c 'yes | /opt/ignite/apache-ignite/bin/control.sh --set-state ACTIVE'
Warning: the command will change state of cluster with name "fc4636efa81-50c9c9bd-a798-46a0-992b-c821b80f623f" to ACTIVE.
Press 'y' to continue . . . Control utility [ver. 2.15.0#20230425-sha1:f98f7f35]
2023 Copyright(C) Apache Software Foundation
User: root
Time: 2023-10-05T05:50:44.866
Command [SET-STATE] started
Arguments: --set-state ACTIVE
--------------------------------------------------------------------------------
Cluster state changed to ACTIVE.
Command [SET-STATE] finished with code: 0
Control utility has completed execution at: 2023-10-05T05:50:45.445
Execution time: 579 ms

## 클러스터 상태 확인
$ docker exec ignite bash -c 'yes | /opt/ignite/apache-ignite/bin/control.sh --state'
Control utility [ver. 2.15.0#20230425-sha1:f98f7f35]
2023 Copyright(C) Apache Software Foundation
User: root
Time: 2023-10-05T05:51:54.598
Command [STATE] started
Arguments: --state
--------------------------------------------------------------------------------
Cluster  ID: e6f53c11-62a4-4fec-8259-ae2a43ce29d5
Cluster tag: busy_burnell
--------------------------------------------------------------------------------
Cluster is active
Command [STATE] finished with code: 0
Control utility has completed execution at: 2023-10-05T05:51:54.902
Execution time: 304 ms
```

이제, 간단한 기능테스트를 해볼 수 있는 환경을 구성하였습니다.

# How to use?

**JAVA thin client로 캐시로 사용하는 방법과, Ignite JDBC를 통해 SQL데이터를 처리할 수 있는 방안 두 가지**를 간단하게 살펴보겠습니다. maven 기준 하단 의존성이 필요합니다.

```xml
<dependencies>
    <dependency>
        <groupId>org.apache.ignite</groupId>
        <artifactId>ignite-core</artifactId>
        <version>2.15.0</version>
    </dependency>
</dependencies>
```

## 1. Using with java-thin-client

단순하게 캐시를 하나 만들고, put/get/count 정도를 해주는 로직입니다. 하단은 단순한 데이터 처리처럼 보이지만, 실제 운영 환경에서 초당 수만건 처리도 별다른 CPU 리소스 사용 없이도 너끈히 가능합니다. 개인적인 선호도에 따라, 오퍼레이션 실패 시 Retry 기능도 적절하게 구현해서 첨가한다면 더욱 강력한 프로그램이 되겠죠? ^^

```java
import org.apache.ignite.Ignition;
import org.apache.ignite.cache.CachePeekMode;
import org.apache.ignite.client.ClientCache;
import org.apache.ignite.client.ClientCacheConfiguration;
import org.apache.ignite.client.IgniteClient;
import org.apache.ignite.configuration.ClientConfiguration;

import java.util.HashMap;
import java.util.HashSet;

import static org.apache.ignite.cache.CacheWriteSynchronizationMode.FULL_SYNC;

public class IgniteThinClientTest {

  public static void main(String[] args) {
    final ClientConfiguration igniteConfiguration = new ClientConfiguration()
        .setAddresses("127.0.0.1:10800")
        .setPartitionAwarenessEnabled(true)
        .setTimeout(5000);
    final IgniteClient igniteClient = Ignition.startClient(igniteConfiguration);

    final String cacheName = "ignite:cache";
    ClientCacheConfiguration igniteCacheConfiguration = new ClientCacheConfiguration();
    igniteCacheConfiguration.setWriteSynchronizationMode(FULL_SYNC);
    igniteCacheConfiguration.setBackups(1);
    igniteCacheConfiguration.setName(cacheName);
    igniteCacheConfiguration.setStatisticsEnabled(true);
    igniteClient.getOrCreateCache(igniteCacheConfiguration);

    ClientCache<String, String> cache = igniteClient.cache(cacheName);
    cache.put("key1", "abcde1");
    System.out.println("key1=>"+cache.get("key1"));
    System.out.println("Size=>"+cache.size(CachePeekMode.ALL));

    cache.putAll(new HashMap<String, String>() {{
      put("key2", "abcde2");
      put("key3", "abcde3");
      put("key4", "abcde4");
    }});
    System.out.println("GetAll=>"+
        cache.getAll(new HashSet<String>() {{
          add("key2");
          add("key3");
          add("key4");
        }})
    );
    System.out.println("Size=>"+cache.size(CachePeekMode.ALL));

    cache.remove("key1");
    System.out.println("Size=>"+cache.size(CachePeekMode.ALL));

    cache.clear();
    System.out.println("Size=>"+cache.size(CachePeekMode.ALL));

    igniteClient.close();
  }
}
```

<결과>

```plain
key1=>abcde1
Size=>1
GetAll=>{key2=abcde2, key3=abcde3, key4=abcde4}
Size=>4
Size=>3
Size=>0
```

추가로 하단을 읽어보시면, 나름 트랜잭션과 같은 고급 기능도 있으니, 참고하시면 좋겠습니다. (빙산의 일각만 소개함)  
참고) <https://ignite.apache.org/docs/latest/thin-clients/java-thin-client>

## 2. Using with JDBC

SQL기반으로 데이터 처리하는 영역은 갈수록 광범위해지고 있습니다. 특히나, JAVA에서는 JDBC라는 강력한 인터페이스를 제공하며, 이를 잘 구현해놓으면 다양한 데이터처리를 SQL로 쉽게 접근하여 처리 가능합니다. Ignite에서도 JDBC 드라이버를 제공하고, 이를 기반으로 SQL로 데이터 질의가 가능합니다.

구현 자체는 기존 SQL 서버들과 붙는 것과 크게 다르지 않습니다. 단지, UPSERT 구문 및 각 데이터베이스별로 제공하는 일부 특이한 쿼리 패턴을 제외하고는.. ^^

```java
import java.sql.*;

public class IgniteJDBCTest {

  public static void main(String[] args) throws ClassNotFoundException, SQLException {

    Class.forName("org.apache.ignite.IgniteJdbcThinDriver");
    Connection conn = DriverManager.getConnection("jdbc:ignite:thin://127.0.0.1:10800");
    Statement stmt = conn.createStatement();
    stmt.execute("create table if not exists person (\n"
                     + "  name varchar, \n"
                     + "  details varchar, \n"
                     + "  primary key(name)\n"
                     + ") with \"backups=1\"");
    stmt.execute("MERGE INTO person (name, details) VALUES ('key1', 'abcde1')");
    stmt.execute("MERGE INTO person (name, details) VALUES ('key2', 'abcde2')");
    stmt.execute("MERGE INTO person (name, details) VALUES ('key3', 'abcde3')");
    stmt.execute("MERGE INTO person (name, details) VALUES ('key4', 'abcde4')");
    {
      ResultSet rs = stmt.executeQuery("select * from person");
      while (rs.next()) {
        System.out.println(rs.getString(1) + "=>" + rs.getString(2));
      }
      rs.close();
    }
    {
      ResultSet rs = stmt.executeQuery("select count(*) from person");
      while (rs.next()) {
        System.out.println("Total=>" + rs.getString(1));
      }
      rs.close();
    }
    stmt.close();
    conn.close();
  }
}
```

<결과>

```
key1=>abcde1
key2=>abcde2
key3=>abcde3
key4=>abcde4
Total=>4
```

참고) https://ignite.apache.org/docs/latest/SQL/JDBC/jdbc-driver

# Conclusion

오늘 이 포스팅에서는 Apache Ignite에 대한 간단한 기술 맛보기 정도만 소개를 했습니다. 물론, Ignite 혹은 Gridgain(상용버전)을 서비스에서 잘 사용하고 있는 분들도 분명 많을 것입니다. 일부는 Ignite에 대해 효율성을 공감하실 분도 계실 것이고, 일부는 아직은 아리송한 생각을 가지고 계실 수도 있습니다.

앞서 이야기를 했었지만, 저는 개인적으로 Apache Ignite에 대해서 하단 정도를 가장 큰 강점으로 뽑고 싶습니다. 물론 Ignite가 인메모리데이터이고, 다양한 기능을 제공해주기는 하지만, (개인적인 생각으로는) 결과적으로는 캐시서버일 분, 그 이상의 의미를 부여할 필요는 없다고 봅니다. 

* **Persistence Mode**
* **SQL(JDBC) 지원**
* 분산 캐시
* 스케일 인/아웃

다음 포스팅에서는 위에서 소개를 했던 두가지 내용에 이어서, **분산 캐시 구성 방법에 추가로 모니터링 구성 방안**을 이야기해보도록 하겠습니다. 아, 추가로, **Thin Client 와 JDBC의 두 가지 퍼포먼스를 간단하게 로컬에서 테스트**를 해서 공유를 하는 것도 좋겠네요.

감사합니다.