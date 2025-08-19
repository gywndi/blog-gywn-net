---
title: MySQL에서 Replication Driver 사용 시 장애 취약점 리포트
author: gywndi
type: post
date: 2012-07-06T03:19:24+00:00
url: 2012/07/mysql-replication-driver-error-report
categories:
  - MySQL
tags:
  - MySQL
  - Replication

---
# Overview

MySQL에서 슬레이브 부하 분산을 하는 방안으로 Replication Driver 기능을 제공하는 jdbc 내부적으로 지원합니다. Replication Driver를 사용하면 상당히 간단하게 마스터/슬레이브 활용을 할 수 있고 어느정도의 Failover는 가능합니다.

하지만 서비스 적용을 위해 Failover테스트 도중 치명적인 문제점이 발생하였습니다. 관련 포스팅을 하도록 하겠습니다. ^^

# 사용 방법

Replication Driver 사용 시 ReadOnly 옵션을 True/False 상태에 따라 마스터/슬레이브 장비를 선택합니다.

아래 그림처럼 ReadOnly이 False이면 마스터 장비에 쿼리를 날리고, True이면 슬레이브에 쿼리를 날리는 구조입니다. 그리고 로드발란싱 기능을 사용하면, 슬레이브 서버 부하 분산할 수 있습니다.

![MySQL Replication Driver](/img/2012/07/MySQL-Replication-Driver.png)

Oracle에서 제시한 Replication Driver 사용 방법입니다.

```
import java.sql.Connection;
import java.sql.ResultSet;
import java.util.Properties;

import com.mysql.jdbc.ReplicationDriver;

public class ReplicationDriverDemo {

  public static void main(String[] args) throws Exception {
    ReplicationDriver driver = new ReplicationDriver();

    Properties props = new Properties();

    // 로드발란싱 옵션 설정
    props.put("autoReconnect", "true");
    props.put("roundRobinLoadBalance", "true");

    // 접속 정보 설정
    props.put("user", "foo");
    props.put("password", "bar");

    Connection conn = driver.connect("jdbc:mysql:replication://master,slave1,slave2,slave3/test", props);
    conn.setAutoCommit(false);

    // 마스터 접근
    conn.setReadOnly(false);
    conn.createStatement().executeUpdate("UPDATE alt_table SET a = 1;");
    conn.commit();

    // 슬레이브 접근
    conn.setReadOnly(true);
    ResultSet rs = conn.createStatement().executeQuery("SELECT a, b FROM alt_table");
  }
}
```

참고자료: http://dev.mysql.com/doc/refman/5.5/en/connector-j-reference-replication-connection.html

# 기능 테스트

실제 상용 서비스 투입을 위해 여러 장애 상황을 구현해보았으며, Replication Driver 동작 상태에 관해 살펴보았습니다.

**결론적으로 말하면, 상용 서비스에서는 사용해서는 안될 취약점을 있었습니다.** 

특히 Connection Pool 환경에서는 말도 안되는 현상이죠.

### Case 1 &#8211; 슬레이브장비가 죽은 경우

슬레이브 장비 중 하나 가 죽은 경우에는 Replication Driver에서 자동으로 감지하고 다른 슬레이브로 데이터 요청 쿼리를 보냅니다. DB 접속을 공인 아이피로 통신할 지라도 접속 지연 현상은 발생하지 않습니다. 아마도 내부적으로 ICMP 프로토콜 통신을 하며 주기적으로 슬레이브 장비 구동 유무를 체크하는 듯 합니다.^^;;

![MySQL Replication Driver Failover1](/img/2012/07/MySQL-Replication-Driver-Failover1.png)

### Case 2 &#8211; 슬레이브가 모두 죽은 경우

Master와만 통신이 가능할 뿐 슬레이브와는 통신이 불가(당연한 이야기겠지만)합니다. 하지만 슬레이브 DB가 정상적으로 돌아오게 되면 자동으로 상태가 복구됩니다.

![MySQL Replication Driver Failover2](/img/2012/07/MySQL-Replication-Driver-Failover2.png)

### Case 3 &#8211; 마스터가 죽은 경우

말도 안되는 장애 현상이 발생했습니다. 마스터가 죽은 경우에는 아래와 같이 **슬레이브가 멀쩡하게 살아있는데도 데이터를 읽을 수가 없습니다.** 일반적인 서버 데이터 작업이라면, 마스터가 죽어도 슬레이브 서버에서 읽기가 가능해야 한 상태, 즉 트랜잭션이 불필요한 READ 로직은 멀쩡해야 합니다. 그러나, 마스터가 죽으면 슬레이브에서도 데이터를 읽어올 수 없기 때문에 결과적으로 전체 서비스 마비가 발생합니다.

![MySQL Replication Driver Failover3](/img/2012/07/MySQL-Replication-Driver-Failover3.png)

하지만, 더욱 더 황당한 상황이 벌어졌습니다.

Connection을 공유(Connection Pool 사용 시)하는 경우 장애가 발생했던 마스터 서버를 복구하였다 할 지라도, 서비스가 정상적으로 돌아오지 않는다는 것입니다. Reconnect 옵션이 활성화되어 있어도 Connection은 정상적으로 돌아오지 않았으며, Connection을 다시 맺어줘야 정상적으로 돌아옵니다. Connection을 공유하는 상황에서 Connection을 다시 맺는 것은 곧 어플리케이션을 재시작하는 것과 거의 비슷한 상황이라고 볼 수 있겠죠. (물론 프로그램적으로 풀 수도 있겠지만, jdbc driver 외적인 요소로 여기서 언급할 필요는 없다고 생각합니다.)

![MySQL Replication Driver Failover4](/img/2012/07/MySQL-Replication-Driver-Failover4.png)

아래는 Connection Pool 환경을 구현하기 위해 부끄럽지만, 간단하게 작성한 JAVA 소스입니다.

```
import java.sql.*;
import java.util.Properties;
import com.mysql.jdbc.ReplicationDriver;
public class MysqlReplicationConnection  extends Thread{
    public static void main(String[] args) throws Exception {
        long currentMiliSecond = System.currentTimeMillis();

        ReplicationDriver driver = new ReplicationDriver();
        Connection conn = null;
        ResultSet rs = null;
        Statement stmt = null;
        Properties props = new Properties();
        props.put("autoReconnect", "yes");
        props.put("maxReconnects", "1");
        props.put("autoReconnectForPools", "true");
        props.put("roundRobinLoadBalance", "true");
        props.put("user", "dba");
        props.put("password", "");
        conn = driver.connect("jdbc:mysql:replication://master:3306,slave1:3306,slave2:3306/dbatest", props);

        while(true){
            try{
                /*************************************
                * Read Test - Slave
                * *************************************/
                conn.setAutoCommit(false);
                conn.setReadOnly(true);
                stmt = conn.createStatement();

                // Print Server Hostname
                rs = stmt.executeQuery("show variables like 'hostname';");
                while(rs.next()){
                    System.out.print("[Select]"+rs.getString(1)+" : "+rs.getString(2));
                }
                rs.close();

                rs = stmt.executeQuery("select count(*) from test;");
                while(rs.next()){
                    System.out.println(" : "+rs.getInt(1));
                }
                rs.close();

                System.out.println("[Time]=========["+(System.currentTimeMillis()-currentMiliSecond-1000)+"]=========");
                currentMiliSecond = System.currentTimeMillis();

                conn.commit();
                stmt.close();

                /*************************************
                * Write Test
                * *************************************/
                conn.setReadOnly(false);

                stmt = conn.createStatement();
                stmt.executeUpdate("insert into test (j) values ('1');");
                rs = stmt.executeQuery("show variables like 'hostname';");
                while(rs.next()){
                    System.out.println("[Insert]"+rs.getString(1)+" : "+rs.getString(2));
                }
                conn.commit();
                rs.close();
                stmt.close();
            }catch(Exception e){
                System.out.println(e);
                //try{conn.close();} catch (Exception sqlEx) {}
                //try{conn = driver.connect("jdbc:mysql:replication://kthdba02:3306,kthdba03:3306,kthdba04:3306/dbatest", props);} catch (Exception sqlEx) {}
            }

            // Sleep 1 Second
            try {
                sleep(1000);
            } catch (InterruptedException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            }
        }
    }
}
```

위와 같은 문제는 Replication Driver를 사용 시에만 발생할 뿐, jdbc로 직접적인 Connection을 맺는 경우에는 발생하지 않습니다. 물론 슬레이브 접속을 다음과 같이 별도 로드발란싱하는 형식으로 Connection으로 수행해도 관련 문제는 발생하지 않습니다.

```
jdbc:mysql:loadbalance://slave1-pri,slave2-pri/dbatest?loadBalanceConnectionGroup=conn&loadBalanceEnableJMX=true
```

Commit/Rollback이 명시적으로 호출되면 다른 서버와 번갈아가며 쿼리가 질의되며, 슬레이브 중 한 대가 죽어도 정상적으로 동작합니다. 쿼리 결과 예외 상황 발생 시 해당 쿼리를 다른 쪽으로 다시 질의하는 방식으로 이루어집니다. 단, 공인아이피로 하는 경우 장애 발생 서버로 쿼리 질의 후 예외 상황 인지 시까지 상당한 시간이 걸릴 수 있으므로 반드시 사설 아이피 대역으로 통신하시기 바랍니다.

# 기술 지원 그 후..

주요 서비스 몇 개에 Oracle로부터 기술 지원을 받기 위해 유지보수 계약을 체결하였기에, 관련 문제 상황에 대해서 SR을 진행하였습니다. 2주 정도 관련 문제로 시달렸으며, 개인적인 생각으로는 불필요한 로그도 상당히 요청하고 엉뚱한 부분만 자꾸 지적하였습니다.

### 기술 지원 요청

아래와 같이 Oracle로 기술지원 요청을 하였습니다. 그리고 전화 상으로 Connection을 공유하는 상황이라고 설명을 하였습니다.

```
문제 설명: jdbc에서 ReplicationDriver 사용 중 Master 장비에서 장애가 난 경우 Master 복구 이후에 Reconnect이 되지 않는 현상이 있습니다.
ReplicationDriver에 전달하는 Properties 정보는 하단과 같습니다.

Properties props = new Properties();
props.put("autoReconnect", "yes");
props.put("failOverReadOnly", "yes");
props.put("roundRobinLoadBalance", "true");

Slave 특정 노드 장애 시 정상적으로 다른 노드에서 select가 일어나나, 문제는 마스터 장애 시에는 "com.mysql.jdbc.exceptions.jdbc4.CommunicationsException: Communications link failure" 메시지와 함께 장애 현상이 발생합니다.
Slave에서 Select도 불가할 뿐만 아니라, Master가 정상적으로 재 구동되어도 기능은 정상적으로 돌아오지 않습니다. 즉 Application을 재시작해야 비로서 서비스가 정상화됩니다.

관련 무슨 문제가 있는지, 정상적인 현상인지 혹은 버그 문제인지 확인 부탁 드립니다.
```

### 기술 지원 결과

Replication Driver 사용 시 발생했던 모~든 문제는 의도된 결과로 소스 수정이 불가하다는 답변을 받았습니다. 관련 샘플 JAVA 프로그램을 받았으나, Connection을 공유하는 상황이 아닌, 매번 직접 DB로부터 Connection을 맺는 방식이었습니다. (관련 첨부를 다시 다운받으려고 들어갔으나, 현재 받을 수가 없네요)

```
앞서 드렸던 답변에서와 같이, replication driver 의 이같은 동작은 의도된 동작입니다.

2012-06-27 09:34 AM
&gt; I consulted the developers and they said that this behavior is made for purpose.

2012-06-28 08:43 AM
&gt; The autoReconnect will restore connections to the slaves, but not to the master.
=&gt; 고객님께서 생각하고 계신 autoReconnect 는 master 가 down 된 이후 복구되었을 때 다시 master로 reconnect 하는 것이 아니라, connection 을 slave 로 restore 하기 위한 것입니다.

replication driver 의 이와 같은 동작은 의도된 것이며, autoReconnect 는 master 로 reconnect 하기 위한 paratmeter 가 아닙니다.
고객님께서 driver 문제로 판단하시는 이와 같은 구현방식에 불편함이 있으실 수 있습니다만, driver 수정은 어려울 것으로 보입니다.

Review 후 SR update 바랍니다.

감사합니다.
```

# Conclusion

MySQL에서 Replication Driver를 사용하면 쉽게 마스터/슬레이브 서버 접속이 가능하나, **마스터 장애시 엄청난 장애가 발생할 수 있는 잠재적인 포인트**가 있습니다.

MySQL이 SUN을 인수하면서 부록(?)으로 따라온 오픈소스일지라도, 일단은 기술 지원을 하는 만큼은 제대로 응대를 해줘야하는 것이 아닐까요? 고객 계약에만 혈안되어 제재 가하기 보다는.. -\_-;; 다시는 오라클로부터 어떠한 답변도 기대하지 않을 것을 다짐했습니다.

서비스 부하 분산을 위해 슬레이브에서 로드발란싱이 필요한 경우에는 다음과 같이 **jdbc:mysql:loadbalance://db1,db2..** 형식으로 사용하시기 바랍니다. 단 사설 아이피로 접속을 해야 장애 발생 시에도 유연하게 서비스가 동작합니다.

혹은 개인적으로 jdbc를 일부 수정하는 것도 좋은 방안입니다. (내부 소스를 까보니 크게 수정이 어려울 것 같지는 않습니다. ^^)

이미 Replication Driver를 사용하고 있다면, 관련 문제점을 반드시 진단하시기 바랍니다. ^^