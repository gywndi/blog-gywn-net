---
title: JDBC의 autoReconnect 파라메터가 저지른 일!
author: gywndi
type: post
date: 2017-10-31T00:00:00+00:00
url: 2017/10/jdbc-insane-autoreconnect
categories:
  - MariaDB
  - MySQL
  - Research
tags:
  - autoReconnect
  - connector
  - jdbc
  - MySQL

---
세상에 말도 안되는 일이 일어났습니다.

서비스가 정상적으로 동작하기 위해서는, 아무래도 데이터베이스가 필수인데.. 이 데이터베이스로부터 쉽게 데이터를 주고받을 수 있게 디비별/언어별 중간 역할을 해주는 것이 바로 Driver입니다.

MySQL역시 자바에서 원활하게 데이터 처리를 수행할 수 있도록 `connector/j`라는 녀석을 Oracle에서 배포를 하는데.. 오늘은 이 녀석이 제공해주는 기능인 `autoReconnect` 파라메터가 저지르는 일에 대해서 얘기를 해보고자 합니다.

# autoReconnect는 무슨 일을 하는가?

파라메터 이름 그대로.. 자동으로 커넥션을 다시 맺어준다는 의미입니다. 데이터베이스 역시 서버로 구동하는 프로그램의 한 축이기에.. 클라이언트가 맺은 커넥션이 절대 끊어지지 않는다고 보장할 수 없습니다.

문제는 이렇게 예기치 않게 커넥션이 단절된 경우, 이에 대한 후처리(다시 커넥션을 맺는)를 100% 어플리케이션에서 구현을 해야합니다만.. 경우에 따라서 이런 처리가 불가한 경우도 있습니다.

JDBC에서는 `autoReconnect` 파라메터를 제공하여, 이렇게 커넥션이 끊어진 상황에서 클라이언트 레벨에서 커넥션을 다시 맺어주는 기능을 제공해줍니다. 물론.. 중간 `socketTimeout`으로 인해 발생한 **Communications link failure** 에 대한 예외 처리는 어플리케이션에서 감내해야겠지만요.

# 커넥션은 어떠한 상황에서 끊어지길래?

의도치않은 커넥션 단절은 대략 세 가지 정도로 축약해볼 수 있습니다.

1. WAIT_TIMEOUT
2. Server Failure
3. socketTimeout (JDBC)

### 1. wait_timeout

MySQL에서는 `wait_timeout`(기본값 8시간)동안 쿼리가 없는 세션들을 정리합니다. 그래서 이런 의도치 않은 현상을 방지하기 위해서는 주기적으로 Validation를 날려서 사용 중인 커넥션이니, 강제로 죽이지 말라고 디비에 알려줘야 하죠.(대부분 커넥션 풀에서는 이 설정이 있어요.)

### 2. Server Failure

다른 사항은.. 말그대로.. 장애난 경우. 예기치 않은 장애로 커넥션이 끊어질 수 있습니다. 부연 설명은 생략~

### 3. socketTimeout

마지막 하나는.. JDBC에서 파라메터로 제공을 해주는 socketTimeout에 의한 것입니다. 쿼리를 실행하였는데, socketTimeout(밀리세컨드 단위)동안 서버로부터 응답이 오지를 않으면 강제로 **클라이언트 레벨(JDBC)에서 이 세션은 죽었어**하고 강제로 끊어버립니다.

특정 슬로우 쿼리들이 커넥션풀을 점유하는 현상을 방지하기 위해.. 사용할 수도 있고, 갑작스러운 서버 행업으로 인하여 비정상적으로 커넥션이 넘어가지 않는 현상을 방지하기 위해 쓰일 수도 있습니다. (참고로 제 경우는 후자입니다.)

# 그래서, 무엇이 문제길래?

오늘 autoReconnect과 엮여서 말도안되는 문제 상황을 저지르는 파라메터는 바로 이 socketTimeout입니다.

```plain
jdbc:mysql://127.0.0.1:3306/test?autoReconnect=true&socketTimeout=10000
```

autoReconnect의 명성대로.. 디비의 wait_timeout 이슈든, jdbc의 `socketTimeout` 이슈든.. 커넥션에 이상이 있으면, 다시 연결해줄 것이라고 믿고 있었습니다. 믿고 있었죠. 물론.. 다시 연결을 해줍니다만.. 그 과정이 충격적이었을 뿐..

커넥션이 끊기고 `autoReconnect`가 동작하면 **데이터베이스 입장에서 새로운 커넥션**이 맺어질까요? 답은 그럴수도 있고, 그럴수도 없다입니다. -\_-;;

mysql jdbc 소스 중 `com.mysql.jdbc.ConnectionImpl.java` 에서 execSQL 소스를 보시죠. 여기서 `getHighAvailability()` 함수는 `autoReconnect` 파라메터의 boolean 값을 가져오는 역할을 담당합니다.

```java
public ResultSetInternalMethods execSQL(StatementImpl callingStatement, String sql, int maxRows, Buffer packet, int resultSetType, int resultSetConcurrency,
        boolean streamResults, String catalog, Field[] cachedMetadata, boolean isBatch) throws SQLException {
    synchronized (getConnectionMutex()) {
..중략..
    if ((getHighAvailability()) && (this.autoCommit || getAutoReconnectForPools()) && this.needsPing && !isBatch) {
        try {
            pingInternal(false, 0);<
            this.needsPing = false;
        } catch (Exception Ex) {
            createNewIO(true);<
        }
    }
..중략..
}

```

위 코드 내용이라면, autoReconnect를 true로 지정해서 커넥션을 맺었다고 할 지라도 반드시 원하는대로 제대로 동작하지는 않습니다. if 구문을 충족하기 위한 전제조건은 아래와 같습니다.

  1. `autoReconnect` 는 TRUE이어야 한다.
  2. `autoCommit`이 TRUE이거나 `autoReconnectForPools`가 TRUE이어야 한다.
  3. 쿼리가 batch (여러구문을 모아서 처리)로 수행되서는 안된다.

즉.. 세션이 끊어졌을 때 반드시 커넥션이 다시 복구되는 것은 아니라는 말이죠. (저도 코드를 보고 진지하게 알게된 사실..ㅠㅠ)

커넥션에 문제가 있다고 판단하면, needsPing 파라메터를 true로 설정하고 아래 Exception을 던지고, 이 커넥션을 통해서 다시 쿼리가 유입되면, 위 if 조건에 부합하면 커넥션을 복구하는 프로세스로 진입합니다. 물론.. `wait_timeout`과 같이 서버에서 강제로 끊은 경우에는 `createNewIO`를 타면서 새로운 커넥션 아이디를 발급받아 세션이 맺어지겠지만요..

```
Communications link failure
The last packet successfully received from the server was 2,001 milliseconds ago.  The last packet sent successfully to the server was 2,000 milliseconds ago.
```

자.. 위에서 `pingInternal(false, 0)` 부분이 바로 커넥션을 다시 맺을 수 있는지를 내부적으로 체크해보는 부분으로.. 이 메쏘드를 쭉쭉 따라가보면, 결국에는 내부적으로 MySQL 패킷 하나를 서버로 날려보고 정상여부를 판단하는 것을 확인할 수 있습니다.

```java
public void pingInternal(boolean checkForClosedConnection, int timeoutMillis) throws SQLException {
.. 중략 ..
    // Need MySQL-3.22.1, but who uses anything older!?
    this.io.sendCommand(MysqlDefs.PING, null, null, false, null, timeoutMillis);<
}

```

이 과정을 성공적(?)으로 마무리하면, 기존에 맺었던 커넥션 그대로 다시 커넥션이 맺어지는데, 이 말은 `socketTimeout`에 의해 예기치 않게 세션이 망가졌을지라도, PING 패킷이 정상적으로 전달되면 다시 이전 커넥션 아이디 그대로 세션이 유지된다는 말이지요.

아래는 `socketTimeout`이 2초인 상황에서 General Log를 수집해본 것인데.. `sleep(3)`로 분명 소켓타임아웃 예외사항이 발생했음에도, 여전히 쓰레드 아이디(붉은색)은 동일한 것을 확인할 수 있습니다.

```
2017-10-27T14:56:30.044826Z	 8945 Query	select 1 as value, sleep(3)
2017-10-27T14:56:33.050245Z	 8945 Query	select 2 as value, sleep(1)
2017-10-27T14:56:34.054223Z	 8945 Query	select 3 as value, sleep(3)
2017-10-27T14:56:37.059865Z	 8945 Query	select 4 as value, sleep(1)
```

만약 새로운 커넥션을 맺었다면 아래와 같은 데이터 처리가 이루어졌겠죠.

```
2017-10-27T14:59:22.298078Z	 8954 Query	select 1 as value, sleep(3)<
2017-10-27T14:59:24.321421Z	 8955 Connect	test2@localhost on test using TCP/IP
2017-10-27T14:59:24.321912Z	 8955 Query	/* @MYSQL_CJ_FULL_PROD_NAME@ ( Revision: @MYSQL_CJ_REVISION@ ) */SELECT  @@session.auto_increment_increment AS auto_increment_increment, @@character_set_client AS character_set_client, @@character_set_connection AS character_set_connection, @@character_set_results AS character_set_results, @@character_set_server AS character_set_server, @@collation_server AS collation_server, @@init_connect AS init_connect, @@interactive_timeout AS interactive_timeout, @@license AS license, @@lower_case_table_names AS lower_case_table_names, @@max_allowed_packet AS max_allowed_packet, @@net_buffer_length AS net_buffer_length, @@net_write_timeout AS net_write_timeout, @@query_cache_size AS query_cache_size, @@query_cache_type AS query_cache_type, @@sql_mode AS sql_mode, @@system_time_zone AS system_time_zone, @@time_zone AS time_zone, @@tx_isolation AS tx_isolation, @@wait_timeout AS wait_timeout
2017-10-27T14:59:24.322999Z	 8955 Query	SET NAMES utf8mb4
2017-10-27T14:59:24.323189Z	 8955 Query	SET character_set_results = NULL
2017-10-27T14:59:24.323425Z	 8955 Query	SET autocommit=1
2017-10-27T14:59:24.323614Z	 8955 Query	SET autocommit=1
2017-10-27T14:59:24.323810Z	 8955 Query	SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ
2017-10-27T14:59:24.325333Z	 8955 Query	USE `test`
2017-10-27T14:59:24.325553Z	 8955 Query	set session transaction read write
2017-10-27T14:59:24.325762Z	 8955 Query	select 2 as value, sleep(1)
```

지금까지 `socketTimeout`에 의해서 커넥션이 단절되면, 무조건 새로운 커넥션을 맺어서 복구될 것이라고 믿었던 제 입장에서는 엄청난 쇼킹이었습니다. 이 말은 곧, `autocommit`이 1인 상황에서 쿼리 레벨에서 트랜잭션을 묶어서 처리했을 시에 **찌꺼기가 남아있는 세션**을 받을 수 있다는 것을 의미합니다.

이것을 정확하게 인지하지 않고, 무조건 새로운 세션을 할당받을 것이라고 믿고 있었다면.. 아래같은 처리에서는 의도치않은 결과를 맞이하고 마는 것이죠.

```java
try {
  stmt.execute("begin");
  stmt.execute("insert into test values(concat('1','::',now()))"); <= 3초 걸렸을때<
} catch (Exception e1) {}

try {
  stmt.execute("begin");
  stmt.execute("insert into test values(concat('2','::',now()))");
} catch (Exception e1) {}

```

얼핏 보면, 첫번째 `try..catch` 구문이 `Communications link failure` 예외처리를 받고, 트랜잭션이 튕겼을테니.. 데이터베이스 레벨에서는 분명 롤백처리가 되었을 것이다라고 판단할 수 있겠지만.. 실제 동작은 아래와 같습니다.

```
2017-10-26T09:21:50.732495Z	9 Query	SET NAMES utf8mb4
2017-10-26T09:21:50.732818Z	9 Query	SET character_set_results = NULL
2017-10-26T09:21:50.736314Z	9 Query	begin
2017-10-26T09:21:50.736597Z	9 Query	insert into test values(concat('1','::',now()))
2017-10-26T09:21:53.754453Z	9 Query	begin<
2017-10-26T09:21:53.755653Z	9 Query	insert into test values(concat('2','::',now()))
2017-10-26T09:21:53.755952Z	9 Query	select concat('[',CONNECTION_ID(),'] ',now())
2017-10-26T09:21:53.756401Z	9 Query	commit

```

분명 롤백처리가 되었을 것이라고 기대했던 데이터처리가.. 동일한 세션 아이디에서 다시 처리되었고, 이에 `begin` 구문을 만나면서 데이터베이스 레벨에서 롤백될 것이라 생각했던 처리가 의도치않게 기록되고 마는 것이죠. 물론.. 대부분의 프레임웤과 커넥션 풀에서는 `set autocommit = 0 / 1` 식으로 처리하기 때문에 문제는 없어보이지만.. 얼마든지 사용자 쿼리에 따라 오동작이 발생할 가능성이 있는 것은 여전합니다.

# 그런데 말입니다. 더 큰 문제가 있습니다.

`autocommit`을 true로 쓰는 상황에서 `socketTimeout`을 짧게 가져가버리면.. 더 큰 문제가 발생할 수 있습니다.

단순 SELECT 의 결과가 내가 수행한 쿼리가 아닌 남의 결과값을 받아볼 수 있다는 것이죠. 이 건은 바로 얼마전 올라온 버그에 대한 내용으로.. PING 결과 타이밍에 따라서 바로 이전 쿼리 결과를 사용자가 받게되는 케이스입니다.  
참고: https://bugs.mysql.com/bug.php?id=88242

위 리포팅에 포함된 내용을 보면.. 아주 가끔식 `Communication link failure`가 발생한 결과가 PING 직후에 도달함으로써, 그 이후 결과들이 하나씩 밀리면서, 결과적으로 바로 이전 쿼리 결과를 받게되는 모습을 보여줍니다.

```
>>>>>>>> CORRECT RESULTSET CASE
21:05:03.730718(+0000000 us) >> SELECT 1, sleep(3)
                                  --> Exception : Communications link failure.
21:05:05.738508(+2007790 us) >> PING
21:05:06.730882(+0992374 us) << RESULT of SELECT 1
21:05:06.730946(+0000064 us) << RESLUT of PING
21:05:06.731050(+0000104 us) >> SELECT 2, sleep(1)
                                  --> This will get 2 (Correct result)
21:05:07.731565(+1000515 us) << RESULT of SELECT 2

>>>>>>>> WRONG RESULTSET CASE
21:05:11.733350(+0000000 us) >> SELECT 5, sleep(3)
                                  --> Exception : Communications link failure.
21:05:13.734162(+2000812 us) >> PING
21:05:14.733893(+0999731 us) << RESULT of SELECT 5
21:05:14.733997(+0000104 us) << RESULT of PING
21:05:14.734023(+0000026 us) >> SELECT 6, sleep(1)
                                  --> Exception : ResultSet is from UPDATE. No Data.
21:05:14.734337(+0000314 us) >> SELECT 7, sleep(3)
                                  --> This will get 6 (Mismatch)
21:05:15.734592(+1000255 us) << RESULT of SELECT 6
```

분명 `SELECT 7` 데이터를 요청했음에도, 실상은 그 이전 쿼리 결과인 `SELECT 6`를 받는 것이죠. 즉, 이 말은 서비스 중 쿼리 실행 시간 혹은 네트워크 상황에 따라 현 jdbc에서는 언제든지 다른 쿼리 결과를 보일 수 있는 홀이 존재한다는 말입니다. 물론 `autocommit`이 true인 경우이기는 하지만요. (그치만, 읽기 위주 서비스에서 많이들 쓰시잖아요.)

# 어떻게 해결하나요?

사실 가장 완벽한 해결법은.. 현재로써는 `autoReconnect` 옵션을 사용하지 않는 것입니다. 대부분의 커넥션풀에서는 내부적으로 커넥션 관리를 하기 때문에.. 큰 문제는 없겠지만.. 단지 걱정하는 것은.. 어떤 요소에 의해 대부분의 커넥션이 끊어지는 상황에서 **망가진 커넥션들이 정리될 때**까지 서비스로 이어지는 영향도입니다.

![connection-pool-overflow](/img/2017/10/connection-pool-overflow.png)

위 상태에서는 커넥션풀 내부에 존재하는 데이터베이스와 연결이 끊겨버린 붉은색 커넥션들이 정리되기 전까지는 지속적으로 서비스에 오류가 노출될 것입니다.

그래서.. autoReconnect를 의도에 맞게 동작하도록 jdbc 소스를 약간 수정해보았습니다. 현재 mysql jdbc에서 브랜치를 하나 따서 일부 코드를 수정하였는데.. 수정한 부분은 아래를 참고하시면 됩니다.  
>> https://github.com/mysql/mysql-connector-j/compare/release/5.1&#8230;gywndi:release/5.1

기존 영향도를 최소화하기 위해, 새로운 jdbc 파라메터를 하나 만들고 이 파라메터가 활성화되면, 문제가 생긴 커넥션에서는 핑체크 대신 무조건 새로운 커넥션을 맺도록 하는 것입니다. 굳이, 어떤 문제 요소가 있어서 클라이언트에서 강제로 끊어버린 세션을 초기화없이 재활용할 이유도 없기 때문이죠.

이 상태로.. 버그리포팅에 포함된 프로그램(데이터 불일치 발생 시 종료됨)으로 6만번 이상 시뮬레이션을 해본 결과, 앞서 버그리포팅에서 간헐적으로 발생했던 데이터 불일치 현상은 더이상 발생하지 않았습니다. 🙂

```
The last packet successfully received from the server was 2,002 milliseconds ago.  The last packet sent successfully to the server was 2,002 milliseconds ago.
>> Query-2 : found : 116032 ==> 116032<
>> Query-1, key(116033) : exception : Communications link failure

The last packet successfully received from the server was 2,006 milliseconds ago.  The last packet sent successfully to the server was 2,006 milliseconds ago.
>> Query-2 : found : 116034 ==> 116034
```

현재 이 내용을 바탕으로 Percona 쪽에 진지하게 검토를 요청해놓았고, 최대한 빠르게 해결점을 찾아볼 생각입니다. (또다시 Percona와 한동안 시끄러운 논쟁을 하게되겠죠. ㅠㅠ)

원인 분석과 해결 방안도 제시했으니.. 빠른 픽스를 해줬으면 하네요. ㅋㅋㅋ

# 그래서 무엇을 배웠는가?

**하나. jdbc에서 `socketTimeout`을 처리하는 방식이 예상과는 많이 다르다는 것을 제대로 알았습니다.** 

비록 socketTimeout을 넘어선 쿼리가 수행되어 세션이 비정상적으로 끊길지라도.. 이 세션 종료는 그냥 자바에서 문제가이다정도로만 마킹할 뿐.. 실제로 세션을 끊지 않는다는 이해가 잘 되지 않는 프로세스를 제대로 체감했죠. ㅋㅋ 즉, jdbc에서는 끊겼다고 예외사항을 말해주지만, 여전히 데이터베이스와의 연결은 끊어지지 않았다는 것..

**둘. 대충 알아서는 안된다는 것. 이상하면 분석해봐야한다는 것을 뼈저리게 느꼈습니다.**

소스를 쭉 따라가면서 느낀 것은.. 생각보다 `autoReconnect`가 동작하기까지 많은 조건이 있어야한다는 것이었죠. 세션이 끊어지면 무조건 새로운 세션으로 연결될 것이라 생각해왔기 때문에.. `autoReconnect` 옵션을 간과했던 점.. 제대로 읽어보지 않았던 점.. 반성합니다.

**마지막으로.. 역시 삽질은 배신을 하지 않습니다.**

횡설수설 긴 글.. 이만 마칩니다.