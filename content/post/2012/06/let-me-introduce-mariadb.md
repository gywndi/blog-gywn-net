---
title: Maria 1탄 – MySQL의 쌍둥이 형제 MariaDB를 소개합니다.
author: gywndi
type: post
date: 2012-06-18T10:27:47+00:00
url: 2012/06/let-me-introduce-mariadb
categories:
  - MariaDB
  - MySQL
tags:
  - MariaDB
  - MySQL

---
# MariaDB란?

MySQL이 Sun Microsystems로 넘어가면서 당시 MySQL AB 출신들이 따로 나와서 MySQL을 기반으로 한 다른 오픈 소스 기반의 DBMS를 배포했다고 합니다. 바로 MariaDB가 그것이며 MySQL과 유전 정보를 그대로 고수한 진짜 오픈 소스 기반의 DBMS입니다.

현재 Monty Program AB와 MariaDB Community에서 개발하고 있으며, MySQL과 기본적으로 구조 및 사용 방법 등 모두 동일합니다. (동일 소스에서 개발되고 있으니 당연한 말입니다.)

Monty Program AB에 따르면 많은 기능들이 MariaDB에서 먼저 구현을 하고 그 후 MySQL에도 반영이 된다고 하는데, 마치 CentOS와 Redhat 리눅스 관계 같다는 생각이 듭니다.^^

[GPL v2](http://kb.askmonty.org/en/mariadb-license/) 라이선스에 따르기 때문에, Oracle의 횡포로부터 상당히 자유롭습니다. 사실 Oracle에서 MySQL 관련하여 현재는 오픈 소스 정책을 고수하고 있지만, 언제 갑자기 그들의 정책을 폐쇄적으로 바꿀 지 모르기 때문에 상당히 호기심이 가는 제품입니다.

# MariaDB vs MySQL 설치 방법

설치 방법은 MySQL과 동일합니다.

물론 컴파일 시에는 사용하고자하는 스토리지 엔진 기능 on/off를 위해 추가/변경이 될 수 있겠지만, RPM방식 혹은 TAR 압축 해제하여 DB를 설치해도 잘 구동됩니다.

MySQL 설치 방법은 [리눅스에 MySQL 설치하기(CentOS 5.6)](/2011/12/mysql-installation-on-linux/) 블로그 포스팅을 참고하세요. (심볼릭 링크 변경 부분만 다릅니다.)

# MariaDB vs MySQL 스토리지 엔진

MariaDB 5.3에서 기본적으로 제공하는 스토리지 엔진은 다음과 같습니다.

```
+------------+---------+--------------+------+------------+
| Engine     | Support | Transactions | XA   | Savepoints |
+------------+---------+--------------+------+------------+
| MEMORY     | YES     | NO           | NO   | NO         |
| MRG_MYISAM | YES     | NO           | NO   | NO         |
| FEDERATED  | YES     | YES          | NO   | YES        |
| BLACKHOLE  | YES     | NO           | NO   | NO         |
| CSV        | YES     | NO           | NO   | NO         |
| Aria       | YES     | NO           | NO   | NO         |
| ARCHIVE    | YES     | NO           | NO   | NO         |
| MyISAM     | YES     | NO           | NO   | NO         |
| InnoDB     | DEFAULT | YES          | YES  | YES        |
| PBXT       | YES     | YES          | YES  | NO         |
+------------+---------+--------------+------+------------+
```

기본 제공되는 스토리지 엔진 중 다음 3개를 눈여겨볼 필요가 있습니다.
  * FEDERATED (트랜잭션 제공)
    - 원격 DB 서버 테이블에 네트워크로 접근하는 스토리지 엔진으로 기존
    - 원격 DB에서 로컬 DB로 결과 값만 전달한다는 점에서 MySQL에 기본으로 장착된 FEDERATED와 가장 큰 차이점이 있음
    - MariaDB에서는 FEDERATEDX라는 새로운 네이밍을 사용

  * 차세대에 MyISAM 스토리지 엔진을 대체하기 위해 개발 
    - MyISAM에서 파생되었으며, Crash-Safe를 목표로 진행 중, 부분적으로 Transaction을 제공

  * PBXT(트랜잭션 제공) 
    - Transaction Log 에 선 기록 없이 바로 DB에 기록
    - Maria5.5부터는 더이상 유지보수를 제공하지 않으므로 기본 스토리지 엔진에서 제외

위 기본 스토리지 엔진 외에 Plugin으로 제공되는 스토리지 엔진을 추가로 설치할 수 있습니다.

  * OQGRAPH  
    - Graph 기능을 제공하는 스토리지 엔진.  
    (Maria5.5에는 기본으로 Plugin이 들어있지 않음)

```sql
MariaDB> INSTALL PLUGIN oqgraph SONAME 'ha_oqgraph.so';
```

  * SphinxSE
    - Full-Text Searching이 필요할 때 사용할 수 있는 스토리지 엔진.  
    단, SphinxSE은 어디까지나 Sphinx의 일부분이며, 스토리지 엔진 사용을 위해서는 Sphinx 데몬을 별도로 설치 필요.
```sql
    MariaDB> INSTALL PLUGIN sphinx SONAME 'ha_sphinx.so';
```

참고로 MySQL 5.5에서 기본적으로 제공하는 스토리지 엔진 리스트입니다

```
+------------+---------+--------------+------+------------+
| Engine     | Support | Transactions | XA   | Savepoints |
+------------+---------+--------------+------+------------+
| FEDERATED  | NO      | NULL         | NULL | NULL       |
| MRG_MYISAM | YES     | NO           | NO   | NO         |
| MEMORY     | YES     | NO           | NO   | NO         |
| BLACKHOLE  | YES     | NO           | NO   | NO         |
| MyISAM     | YES     | NO           | NO   | NO         |
| CSV        | YES     | NO           | NO   | NO         |
| ARCHIVE    | YES     | NO           | NO   | NO         |
| InnoDB     | DEFAULT | YES          | YES  | YES        |
+------------+---------+--------------+------+------------+
```

# MariaDB vs MySQL SQL Join

MariaDB 5.3으로 넘어오면서 조인 퍼포먼스가 향상되었는데, 그 중 괄목할 만한 사항은 Semi-join 서브쿼리 성능 향상에 관련된 내용입니다.

예를 들어서 다음과 같은 SQL이 유입되었다고 가정해 보자면..

```
select * from Country
where
  Continent='Europe' and
  Country.Code in (select City.country
                   from City
                   where City.Population>1*1000*1000);
```

MySQL 5.5 인 경우 위 쿼리는 아래와 같이 Country -> City 테이블 순으로 쿼리가 실행되며, Continent 조건이 없는 경우 Full-Table Scan이 발생합니다.

![Semi Join Sub Query(1)](/img/2012/06/image2012-6-18-17-34-34.png)

그러나 MariaDB5.3에서는 반대로 City -> Country 서브쿼리 부분이 먼저 풀리고 결과적으로 외부 테이블과 조인 연산하는 방식으로 데이터를 처리합니다. 즉, Continent 조건이 없어도 Full-Table Scan이 발생하지 않는 것이죠.

![Semi Join Sub Query(2)](/img/2012/06/image2012-6-18-17-36-31.png)

조건절에 IN 을 써서 간단하게 작성할 수 있는 SQL 경우(설혹 조건이 10건 미만일 지라도)에도 어쩔 수 없이 Inner Join으로 풀어야 하는 경우가 많았기 때문에, 정말로 반가운 내용입니다.

무엇보다  Optimizer Switch를 확인해보면 Optimizer의 선택의 폭이 MySQL 5.5 대비 상당히 다양한 것을 볼 수 있습니다.^^

#### MariaDB Optimizer Switch

```
MariaDB> SELECT @@optimizer_switch\G
@@optimizer_switch: index_merge=on
                    ,index_merge_union=on
                    ,index_merge_sort_union=on
                    ,index_merge_intersection=on
                    ,index_merge_sort_intersection=off
                    ,index_condition_pushdown=on
                    ,derived_merge=on
                    ,derived_with_keys=on
                    ,firstmatch=on
                    ,loosescan=on
                    ,materialization=on
                    ,in_to_exists=on
                    ,semijoin=on
                    ,partial_match_rowid_merge=on
                    ,partial_match_table_scan=on
                    ,subquery_cache=on
                    ,mrr=off
                    ,mrr_cost_based=off
                    ,mrr_sort_keys=off
                    ,outer_join_with_cache=on
                    ,semijoin_with_cache=on
                    ,join_cache_incremental=on
                    ,join_cache_hashed=on
                    ,join_cache_bka=on
                    ,optimize_join_buffer_size=off
                    ,table_elimination=on
```

#### MySQL 5.5 Optimizer Switch

```
mysql> SELECT @@optimizer_switch\G
@@optimizer_switch: index_merge=on,
                    index_merge_union=on,
                    index_merge_sort_union=on,
                    index_merge_intersection=on,
                    engine_condition_pushdown=on
```

# Conclusion

위에서 나열한 특징 외에도 상당한 차이점이 있으나 내용이 방대하여 세세하게 살펴보지는 못했고, 기존 MySQL 대비하여 성능 및 사용 편의성이 얼마나 좋은지를 다양한 벤치마크 활동을 통해서 알아봐야 합니다.

그렇지만, 현재 Oracle이 MySQL을 인수한 상태이고, 언제든지 내부적인 정책을 변경할 수 있는만큼 지속적으로 검토할 가치가 있는 DBMS임에는 틀림없습니다.

꾸준히 MariaDB를 분석하여 포스팅하겠습니다.^^

**<참고 자료>**
* http://kb.askmonty.org/en/semi-join-subquery-optimizations
* http://kb.askmonty.org/en/mariadb-storage-engines/
* http://dev.mysql.com/doc/refman/5.1/en/switchable-optimizations.html