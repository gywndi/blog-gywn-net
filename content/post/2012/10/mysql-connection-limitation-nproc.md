---
title: CentOS 6.x에서 MySQL 운영 시 반드시 확인해봐야 할 파라메터!
author: gywndi
type: post
date: 2012-10-16T07:48:35+00:00
url: 2012/10/mysql-connection-limitation-nproc
categories:
  - MySQL
tags:
  - Linux
  - MySQL

---
# Overview

MySQL 내부에서는 최대 허용 가능한 Connection을 설정할 수 있습니다. 하지만 OS 파라메터의 제약으로 때로는 임계치만큼 Connection을 늘릴 수 없는 경우가 발생하기도 합니다. 게다가, 만약 OS가 업그레이드되면서 관련 Default Value 가 변경되었다면? 이유없는 장애가 발생할 수도 있는 것이죠.

오늘은 OS 파라메터 중 CentOS 버전 별 nproc 값에 의한 Max Connection 제한에 대해 포스팅하겠습니다.

# Environment

### 1) CentOS 5.8

CentOS 5.x버전의 nproc(Max User Processes) 기본 값은 다음과 같습니다.

```bash
$ ulimit -a | grep processes
max user processes          (-u) 4095
```

### 2) CentOS 6.3

이에 반해 CentOS 6.x버전부터는 `/etc/security/limit.conf`에 nproc에 특별한 설정을 하지 않는 한 1,024를 기본값으로 가집니다.

```bash
$ ulimit -a | grep processes
max user processes          (-u) 1024
```

이 설정은 CentOS 6.x버전부터 사용자 로그인 시 하단 파일에서 1,024 값을 기본값으로 세팅하며, 시스템 리소스를 제한하고자 새로 추가된 설정입니다.

```bash
$ cat /etc/security/limits.d/90-nproc.conf
# Default limit for number of user's processes to prevent
# accidental fork bombs.
# See rhbz #432903 for reasoning.
*      soft    nproc     1024
```

# Connection Test

MySQL DB 재시작 직후 pstree  명령으로 확인을 하면 16개의 데몬이 떠있는 것으로 확인됩니다. 물론 top 혹은 ps 명령어로 확인 시에는 단일 프로세스로 확인됩니다.

```bash
$ pstree | grep mysql
     |-mysqld_safe---mysqld---16*[{mysqld}]
```

이 상태에서 단순 Connection만 늘리는 프로그램을 돌려봅니다. 임계치(2000개)만큼만 Connection을 생성하는 간단한 JAVA 프로그램을 로직이며, Connection Open 이후 별다른 Close 작업을 하지는 않습니다.

아래 로직을 CentOS5.8, CentOS6.3에서 nproc 기본 값과 일부 변경 이후 DB를 재시작하여 테스트를 진행합니다.

```bash
import java.sql.*;
import java.util.Random;
public class Test {
    public static void main(String[] argv) throws ClassNotFoundException, SQLException{
        // Set Connection Limit
        int connLimit = 2000;

        Connection[] conn = new Connection[connLimit];
        Class.forName("com.mysql.jdbc.Driver");

        // Get Connection
        for(int i = 0; i &lt; connLimit; i++){
        System.out.println(i);
        conn[i] = DriverManager.getConnection("jdbc:mysql://10.0.0.101:3306/dbatest","dbatest","");
        }

        // To Keep Java Program - no exit
        Statement stmt = conn[0].createStatement();
        for(int i = 0;;i++){
        stmt.execute("select sleep(5)");
        System.out.println(i+"th!!");
        }
    }
}
```

# Test Result &#8211; CentOS 5.8

### 1) Default (nproc = 4095)

2,000개 신규 Connection생성에는 문제가 없었습니다.

```bash
mysql> select count(*)
    -> from information_schema.processlist;
+----------+
| count(*) |
+----------+
|     2001 |
+----------+
1 row in set (0.01 sec)
```

### 2) nproc 변경 (nproc = 200)

그러나 다음과 같이 nproc 값을 200으로 설정 후 동일한 테스트를 진행합니다.

```bash
## change max user processes limit
$ ulimit -u 200

## DB restart
$ /etc/init.d/mysqld restart
```

신규 Connection을 183개 생성 후 Java 콘솔에서 다음 에러와 함께 프로그램이 종료됩니다.

```bash
Exception in thread "main" java.sql.SQLException: null,  message from server: "Can't create a new thread (errno 11); if you are not out of available memory, you can consult the manual for a possible OS-dependent bug"
```

위 상태에서 Linux 콘솔에서 신규 Connection 생성 시에도 다음과 같은 에러가 발생합니다. 하단의 경우 TCP/IP가 아닌 Socket을 통한 접근입니다.

```bash
$ /usr/local/mysql/bin/mysql -uroot
ERROR 1135 (HY000): Can't create a new thread (errno 11); if you are not out of available memory, you can consult the manual for a possible OS-dependent bug
```

pstree로 확인한 mysqld 프로세스 개수입니다.

```bash
pstree | grep mysql
     |-mysqld_safe---mysqld---199*[{mysqld}]
```

# Test Result &#8211; CentOS 6.3

### 1) Default (nproc = 1024)

앞선 테스트와 동일하게 Java 프로그램을 실행하였을 때 2,000개의 신규 세션을 맺을것으로 기대되나, 1007개 세션 생성 이후 다음과 같은 에러가 발생합니다.

```bash
Exception in thread "main" java.sql.SQLException: null,  message from server: "Can't create a new thread (errno 11); if you are not out of available memory, you can consult the manual for a possible OS-dependent bug"
```

### 2) nproc 변경 (nproc = 4095)

nproc를 4095개로 설정 및 DB재시작 후 앞선 테스트를 동일하게 수행합니다.

```bash
## change max user processes limit
$ ulimit -u 4095

## DB restart
$ /etc/init.d/mysqld restart
```

결과적으로 2000개의 세션을 생성하는데 문제가 전혀 없습니다.

```bash
mysql> select count(*)
    -> from information_schema.processlist;
+----------+
| count(*) |
+----------+
|     2001 |
+----------+
1 row in set (0.01 sec)
```

# Solution

가장 간단한 해결 방안은 limit.conf 파일에 nproc 값을 넣는 방법입니다.

```bash
$ vi /etc/security/limits.conf
## 하단 라인 추가
*      -    nproc     4095
```

MySQL 재시작 후 위 파라메터가 제대로 적용이 됐는 지 확인합니다. Max Processes값이 여전히 1024라면 콘솔에 다시 접속하여 MySQL을 재시작합니다.

```bash
$ cat /proc/&lt;mysql_pid>/limits
Limit             Soft Limit       Hard Limit
Max cpu time          unlimited        unlimited
Max file size         unlimited        unlimited
Max data size         unlimited        unlimited
Max stack size        10485760         unlimited
Max core file size    0            unlimited
Max resident set      unlimited        unlimited
Max processes         4095         4095
Max open files        50000        50000
Max locked memory     32768        32768
Max address space     unlimited        unlimited
Max file locks        unlimited        unlimited
Max pending signals       4095         4095
Max msgqueue size     819200           819200
Max nice priority     0            0
Max realtime priority     0            0
```

Max processes 값이 4095로 상향 조정된 것을 확인할 수 있습니다.

어디에 관련 값을 명시하는 것이 좋을 지는 시스템에 맞게 설정하시면 되겠어요. ^^ 특히나 여러 서버가 동시에 올라오는 공유 서버라면, nproc 파라메터 변경 하나로 전체 프로세스에 영향을 미치며 서버 리소스를 크게 잡을 수도 있기 때문이죠. ㅎ

# Conclusion

Active Session이 1,000개인 상태라면 분명 DB에 상당한 부하가 발생합니다. 예전 벤치마킹에서 Active Session이 50개 이상부터는 QPS가 더이상 증가하지도 않는 결과도 나왔습니다.

하지만 실 사용환경에서는 Active Session이 50개 미만이나, Connection 수는 1,000개 이상 존재하는 경우는 다분합니다. 단순히 Connection만 맺고 특별한 SQL을 실행하지 않으므로 Sleep 상태로 머물러 있는 상태이죠.

이 경우 DB내부 Connection 제한이 아닌 OS Process Limit 개수 영향으로 예기치 않는 문제가 발생할 수 있습니다. 분명 MySQL의 세션은 쓰레드임에도 불구하고, OS에서는 Process로 인식하는 현상은 참으로 놀라운 일이네요. ^^;; 왜그럴지..ㅎㅎ

특히, CentOS 5.x버전에서 CentOS 6.x버전으로 OS를 업그레이드하였다면, 관련 서버 설정을 점검하여 잠재적인 장애 이슈를 사전에 제거할 필요가 있습니다.