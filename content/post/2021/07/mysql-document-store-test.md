---
title: MySQL document store 초간단 테스트
author: gywndi
type: post
date: 2021-07-28T02:00:16+00:00
url: 2021/07/mysql-document-store-test
categories:
  - MySQL
tags:
  - document store
  - MySQL
  - mysqlx

---
# Overview

MySQL을 마치 NoSQL의 저장소처럼 써보겠다는 Document Store!! 만약 memcached plugin처럼 native한 프로토콜로 스토리지 엔진에서 직접적인 데이터 처리를 할 것 같은 꿈만 같은 저장소로 느껴졌습니만..

결론적으로 이야기해보자면.. 단순히 json 타입의 컬럼에 데이터를 넣고 빼기위한 프로토콜일 뿐.. 모든 것이 쿼리로 변환이 되어서 데이터 처리가 이루어집니다.

이에 대해 간단한 테스트 내용을 공유해봅니다.

# Installation

도큐먼스스토어를 활성화시키는 것은 간단합니다. 아래와 같이 mysqlx.so 플러그인만 설치를 하면 됩니다.

```sql
## mysql.session@localhost 계정이 존재해야함.
mysql> INSTALL PLUGIN mysqlx SONAME 'mysqlx.so';

mysql> show variables like '%mysqlx_port%';
+--------------------------+-------+
| Variable_name            | Value |
+--------------------------+-------+
| mysqlx_port              | 33060 |
| mysqlx_port_open_timeout | 0     |
+--------------------------+-------+
2 rows in set (0.00 sec)

mysql> \! netstat -an | grep 33060
tcp46      0      0  *.33060                *.*                    LISTEN
```

참고로, mysql.session 계정이 있어야, 정상적으로 동작합니다. (Docker로 테스트하시는 분들은. ^^ 이부분 유념해주세요.) 이제 테스트를 하기위한 테이블과 데이터를 만들어봅니다.

```sql
mysql> CREATE TABLE `doc01` (
    ->   `i` int(11) NOT NULL AUTO_INCREMENT,
    ->   `doc` json DEFAULT NULL,
    ->   PRIMARY KEY (`i`)
    -> )
mysql> insert into doc01 (doc) values ('{"age": 30, "gender": "man", "info": "dev1"}');
mysql> insert into doc01 (doc) values ('{"age": 31, "gender": "man", "info": "dev2"}');
mysql> insert into doc01 (doc) values ('{"age": 32, "gender": "man", "info": "dev3"}');
mysql> insert into doc01 (doc) values ('{"age": 30, "gender": "man", "info": "dev4"}');

mysql> select * from doc01;
+---+----------------------------------------------+
| i | doc                                          |
+---+----------------------------------------------+
| 1 | {"age": 30, "info": "dev1", "gender": "man"} |
| 2 | {"age": 31, "info": "dev2", "gender": "man"} |
| 3 | {"age": 32, "info": "dev3", "gender": "man"} |
| 4 | {"age": 30, "info": "dev4", "gender": "man"} |
+---+----------------------------------------------+
4 rows in set (0.00 sec)
```

# Java test code

공식 문서에는 다양한 클라이언트(python / js / c# / c++ / java) 등을 제공을 합니다. 다만.. golang 이 공식적으로 없다하니. 왠지 서글픈 기분이 드는구먼요. ㅠㅠ

```java
import com.mysql.cj.xdevapi.*;

public class MyTest {
  public static void main(String[] argv) throws Exception {
    Session mySession = new SessionFactory().getSession("mysqlx://127.0.0.1:33060/test?user=root&password=root");
    Schema myDb = mySession.getSchema("test");
    Collection myColl = myDb.getCollection("doc01");
    DocResult myDocs = myColl.find("age = :age").limit(10).bind("age", 30).execute();
    System.out.println(myDocs.fetchAll());
    mySession.close();
  }
}
```

이 코드를 수행하고 나면, 아래와 같이 테이블에 있는 데이터들이 json 형태로 내려옵니다.

```json
[{"age":30,"gender":"man","info":"dev1"}, {"age":30,"gender":"man","info":"dev4"}]
```

참고로, 만약 다른 테이블을 바라보고 싶다면, 아래와 같이 Collection의 위치를 변경해서 수행을 하면 됩니다.

```cpp
Collection myColl = myDb.getCollection("doc01");
```

# General log (Query log)

제가 위 코드를 바탕으로 확인해보고 싶은 포인트는 정확히 한가지입니다. 데이터 처리 시 파싱 단계 없이, 바로 스토리지 엔진에서 데이터를 끌어오는 것인지!! (의외로 파싱과 옵티마이저 단계가 많은 CPU 리소스를 소모합니다. 특히나, OLTP로 몬스터급 단순 쿼리를 날리는 경우!)

만약 [InnoDB memcached plugin](/2019/09/mysql-innodb-as-cache-server-config/)이나 Handler socket처럼, 별도의 파싱과정 없이 바로 스토리지 엔진에서 데이터를 처리하는 구조라면, 해볼 수 있는 것들이 대단히 많아질 것입니다. 우리에게는 MySQL replication이라는 강력한 복제툴이 있기에. 비휘발성 도큐멘트 스토어도 꿈꿔볼 수 있겠죠.

아쉽게도.. 요청이 아래와 같이 SELECT 쿼리로 컨버팅되어서 처리되는 것을 확인해볼 수 있었습니다. ㅠㅠ

```
2021-07-27T20:28:01.346521Z       34 Query    SELECT doc FROM `test`.`doc01` WHERE (JSON_EXTRACT(doc,'$.age') = 30) LIMIT 10
```

# Conclusion

개인적인 생각으로는.. mysql을 도큐먼트 스토어로 Key/Value로 사용한다는 것 외에는 딱히 좋은 점이 떠오리지 않았습니다.  
제대로 성능 테스트를 해봐야겠지만. General log에 찍혀있는 결과로만 봐서는 InnoDB memcached plugin보다 무엇이 더 유리할지..? 물론, READ촛점이고, JSON타입의 편의성을 생각해보면, 다른 결론을 내볼 수 있겠지만요.

그러나, 성능/효율 측면에서 아쉬움이 남는 개인적인 결론을 지으며, 이번 블로그를 마무리합니다.
