---
title: '[MySQL] Online Alter에도 헛점은 있더구나 – gdb, mysqld-debug 활용 사례'
author: gywndi
type: post
date: 2018-10-12T00:00:52+00:00
url: 2018/10/online-alter-for-varchar
categories:
  - MariaDB
  - MySQL
  - Research
tags:
  - MariaDB
  - MySQL
  - pt-online-schema-change

---
# Overview

MySQL에서도 5.6부터는 온라인 Alter 기능이 상당부분 제공되기 시작했습니다. 인덱스과 칼럼 추가/삭제 뿐만 아니라, varchar 경우에는 부분적으로 칼럼 확장이 서비스 중단없이 가능한 것이죠. 물론 오라클 유저들에게는 당연한 오퍼레이션들이, MySQL에서는 두손들고 운동장 20바퀴 돌 정도로 기뻐할만한 기능들입니다. 물론, 대부분의 DDL을 테이블 잠금을 걸고 수행하던 5.5 시절에도 online alter를 위해 트리거 기반의 pt-online-schema-change 툴을 많이들 사용했었기에.. 서비스 중단이 반드시 필요하지는 않았지만요. ([소소한 데이터 이야기 – pt-online-schema-change](/2017/08/small-talk-pt-osc/))

아무튼 이렇게 online alter가 대거 지원하는 상황 속에서, MySQL의 메뉴얼과는 다르게 잘못 동작하는 부분이 있었는데, 이 원인을 찾아내기 위해서는 MySQL 내부적으로 어떻게 동작을 하는지 알아내기 위해 며칠 우물을 신나게 파보았습니다.

오늘 블로그에서는 지난 일주일간의 삽질에 대해서 공유를 해보고자 합니다.

# VARCHAR size extension

MySQL에서 데이터의 타입이 변경되는 경우에는 테이블 잠금을 잡은 상태에서 데이터 리빌딩을 하기 마련이지만.. VARCHAR 타입의 경우에는 조금 다르게 동작을 합니다. **VARCHAR 칼럼에는 데이터의 사이즈(바이트)를 알려주는 Padding 값이 포함**되어 있는데, 매뉴얼 상으로는 패딩의 바이트 수가 동일한 경우에는 테이블 메타 정보만 수정함으로써 Online Alter 가 진행되는 것이죠.

> The number of length bytes required by a VARCHAR column must remain the same. For VARCHAR columns of 0 to 255 bytes in size, one length byte is required to encode the value. For VARCHAR columns of 256 bytes in size or more, two length bytes are required. As a result, in-place ALTER TABLE only supports increasing VARCHAR column size from 0 to 255 bytes, or from 256 bytes to a greater size. In-place ALTER TABLE does not support increasing the size of a VARCHAR column from less than 256 bytes to a size equal to or greater than 256 bytes. In this case, the number of required length bytes changes from 1 to 2, which is only supported by a table copy (ALGORITHM=COPY)

출처 : https://dev.mysql.com/doc/refman/5.7/en/innodb-online-ddl-operations.html

바이트 단위로 계산이 되기 때문에, 글자수로 기록이 되는 VARCHAR 타입 입장에서는 **캐릭터셋에 따라 글자 수 구간이 달라집니다.** 예를 들어 2바이트를 차지하는 euckr인 경우, 1~127글자 구간과 128이상 구간으로 나누어볼 수 있을 것이고, 4바이트 utf8 캐릭터셋인 utf8mb4 경우에는 1~63글자 구간 그리고 64이상 구간으로 그룹을 지어볼 수 있겠습니다.

간단하게 예를 들어보겠습니다. 우선 하단과 같이 테이블을 만들어보고..

```sql
CREATE TABLE `test` (
  `a` varchar(8) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

알고리즘을 명시적으로 줘서 테스트를 해보면.. 우선 VARCHAR(8) -> VARCHAR(16) 사이즈 확장은 큰 문제 없이 잘 동작을 합니다. (둘다 바이트 수가 255 이하이므로, 동일 패딩 1바이트입니다.)

```sql
mysql> alter table test modify a varchar(16), algorithm=inplace;
Query OK, 0 rows affected (0.04 sec)
```

그러나 63글자를 넘어서 255사이즈로 inplace 알고리즘(online alter)으로 칼럼을 확장하고자 하면, 아래와 같이 에러를 뱉습니다. 에러 메시지를 존중하여, 알고리즘을 COPY로 지정을 해야 **테이블 잠금**을 품고 **데이터 재구성**하는 과정을 거쳐 비로서 정상적으로 칼럼 확장이 마무리되죠. (둘다 바이트 수가 256 이상이므로, 동일 패딩 2바이트입니다.)

```sql
mysql> alter table test modify a varchar(255), algorithm=inplace;
ERROR 1846 (0A000): ALGORITHM=INPLACE is not supported. Reason: Cannot change column type INPLACE. Try ALGORITHM=COPY.

mysql> alter table test modify a varchar(255), algorithm=copy;
Query OK, 1 row affected (0.03 sec)
```

매뉴얼 내용은 제대로 각인되었을 것으로 간주하고.. 이제 오늘 이야기하고자 하는 주제로 넘어가겠습니다.

# Indexed Column Extension

그렇습니다. 이야기대로라면, Padding 조건에 맞는 칼럼이 경우에는 무중단, 리빌딩 없이 순식간에 칼럼 사이즈가 확장되어야 하는 것이 정석이건만.. **인덱스를 품은 VARCHAR칼럼**인 경우에는 그렇지가 않았습니다. 위에서 테스트로 간단하게 생성을 했었던 테이블 기준으로 테스트 케이스를 만들어서 확인해보겠습니다.

```sql
CREATE TABLE `test` (
  `a` varchar(8) DEFAULT NULL,
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

mysql> insert into test select left(uuid(),8);

## 20회 수행
mysql> insert into test select left(uuid(),8) from test;

mysql> select count(*) from test;
+----------+
| count(*) |
+----------+
|  1048576 |
+----------+

```

확실한 차이를 보이기 위해서, 우선 인덱스가 없는 현재 상황에서 VARCHAR(8) -> VARCHAR(16)으로 사이즈를 확장해서 0.02초에 백만건 넘는 데이터의 칼럼 사이즈가 바로 확장이 되는 것을 보이겠습니다.

```sql
mysql> alter table test modify a varchar(16), algorithm=inplace;
Query OK, 0 rows affected (0.02 sec)
Records: 0  Duplicates: 0  Warnings: 0
```

이 상태에서 인덱스를 하나 추가하고 앞과 비슷하게 VARCHAR(16) -> VARCHAR(17)로 확장을 시도해보았는데.. 바로 완료가 될 것이라는 기대와는 다르게.. 초단위로 DDL이 수행되었습니다.

```sql
mysql> alter table test add key ix_a_1(a);
Query OK, 0 rows affected (1.55 sec)
Records: 0  Duplicates: 0  Warnings: 0

mysql> alter table test modify a varchar(17), algorithm=inplace;
Query OK, 0 rows affected (1.64 sec)
Records: 0  Duplicates: 0  Warnings: 0
```

여기에 추가로 인덱스를 하나 더 생성을 해서 VARCHAR(17) -> VARCHAR(18)로 칼럼을 확장을 해보니 인덱스 한개 대비 대략 두배 정도의 시간이 더 소요된 것을 확인할 수 있겠죠.

```sql
mysql> alter table test add key ix_a_2(a);
Query OK, 0 rows affected, 1 warning (4.43 sec)
Records: 0  Duplicates: 0  Warnings: 1

mysql> alter table test modify a varchar(18), algorithm=inplace;
Query OK, 0 rows affected (3.24 sec)
Records: 0  Duplicates: 0  Warnings: 0

```

참고로, 이 alter 구문의 프로파일링은 하단과 같으며.. **altering table 단계에서 병목**이 걸려있습니다. 무언가 내부적으로 이상한 짓을 하고 있는 것이죠. ㅎㅎ 이 당시 상황에서 `performance_schema.metadata_locks`을 확인해볼 수 있다면 약간의 정보를 더 얻을 수 있겠지만.. 대세에 큰 영향은 없습니다. ㅠㅠ 정보가 너무 부족합니다.

```sql
+--------------------------------+----------+
| Status                         | Duration |
+--------------------------------+----------+
| starting                       | 0.000069 |
| checking permissions           | 0.000007 |
| checking permissions           | 0.000005 |
| init                           | 0.000006 |
| Opening tables                 | 0.000297 |
| setup                          | 0.000019 |
| creating table                 | 0.009754 |
| After create                   | 0.000255 |
| System lock                    | 0.000012 |
| preparing for alter table      | 0.000275 |
| altering table                 | 2.993340 |
| committing alter table to stor | 0.014045 |
| end                            | 0.000056 |
| query end                      | 0.000336 |
| closing tables                 | 0.000024 |
| freeing items                  | 0.000041 |
| cleaning up                    | 0.000062 |
+--------------------------------+----------+

```

참고로 이 상황에서 서비스 쿼리가 중단되거나 하지는 않아요. **그냥 내부적으로 InnoDB Buffer Pool I/O가 늘어났을 뿐 서비스 쿼리는 큰 문제가 없습니다.** 문제는 DDL 구문이 오래걸리는 상황이라면, 자연스럽게 **복제 지연**으로 이어질 수 있다는 점인데요. ALTER구문은 데이터를 담고 있는 **그릇이 변경되는 의미**하는 것이기 때문에.. 데이터를 복제하는 슬레이브 입장에서는 DDL 구문 이후에 변경된 그릇 기준으로 생성되는 DML 쿼리를 처리할 수 있습니다.

생각을 해보세요. 1000만건 테이블의 특정 VARCHAR칼럼에 5개 이상의 인덱스가 관여하고 있다면..?? 생각보다 슬레이브 지연 영향도는 심각할 수 있겠죠.

**즉, 순식간에 종료될 것이라 생각했던 Online Alter 구문이 슬레이브 복제 지연에 영향을 줄 수 있다는 점이죠.**

![Replication-Delay](/img/2018/10/Replication-Delay-1024x482.png)

만약 슬레이브 서버들이 어떤 형태로든 서비스에 관여를 하고 있다면.. 이 상황에서 복제 지연 현상은 데이터를 관리하는 데이터쟁이 입장에서는 그다지 듣기좋은 이야기는 아닙니다.

자~ 그렇다면, 도대체 이 현상은 왜 발생했을까요? 다행히 이 이슈 분석을 위해 인덱스 있는 VARCHAR 칼럼이라는 중요한 재현 시나리오는 마련이 되어있군요. 만약 재현이 어려운 상황이라면.. 분석이 정말 난해한 상황이었을 것입니다. ㅋㅋ

# Debugging with gdb

우선 멈춰있는 이 상황에서, MySQL이 내부적으로 어떤짓을 하고 있는지 디버깅을 해봅시다. 알수 없는 무언가를 하고 있는가를 확인해봐야겠죠. 위에서 MySQL이 무언가 알수 없는 것을 처리하는 상황에서 gdb로 아래와 같이 트레이스를 떠봅니다.

```bash
$ gdb -ex "set pagination 0" \
      -ex "thread apply all bt" \
      -batch -p `pidof mysqld` > result.out
```

이렇게하면 외계 문자들이 쭈르륵 떨어질 것인데.. 이중 **OS의 쓰레드 아이디 기준**으로 나온 결과를 보고 현재 이 쓰레드에서 무슨 짓을 하고 있는지 추적을 해봅니다. 참고로, mysql 프로세스 아이디 기준으로 OS 쓰레드 아이디는 아래와 같이 threads 테이블에서 알아낼 수 있어요.

```sql
mysql> select thread_id_os from performance_schema.threads
    -> where processlist_id = &lt;프로세스아이디>;

```

만약 OS의 쓰레드 아이디가 8이었다면.. 이 쓰레드 번호로 검색을 해보면.. 지금 어떤일을 하고있는지 적나라하게 확인할 수 있겠죠. 참고로 여기서는 인덱스 리빌딩(row\_merge\_build_indexes) 관련하여 무슨 짓을 하고 있는 것으로 보여지네요. ㅎ (외계어기는 하지만.. 동일 버전의 소스를 다운받아서 위치를 따라가보면, 대략 무슨 짓을 하고 있는지 이해할 수 있을 듯..)

```bash
$ vi result.out
.. 중략 ..
Thread 8 (Thread 0x7ff8790c3700 (LWP 31032)):
**#0  0x0104ed22 in row_merge_blocks .. storage/innobase/row/row0merge.cc:2784
#1  row_merge .. storage/innobase/row/row0merge.cc:2957
#2  row_merge_sort .. storage/innobase/row/row0merge.cc:3077**
**#3  0x01056454 in row_merge_build_indexes .. storage/innobase/row/row0merge.cc:4550
**#4  0x00f902da in ha_innobase::inplace_alter_table .. innobase/handler/handler0alter.cc:6314
#5  0x007619ec in ha_inplace_alter_table .. sql/handler.h:3604
.. 중략 ..
#15 0xf9c07aa1 in start_thread () from /lib64/libpthread.so.0
#16 0xf98e8aad in clone () from /lib64/libc.so.6
```

# Debugging with mysqld-debug

앞서 의심을 했었던, 인덱스 관련된 무슨 짓꺼리를 하고 있을 것이다라는 심증은 확신으로 바뀌면서.. 이제 조금더 상세하게 디버깅해보도록 하죠. 이번에는 mysqld-debug로 이 작업을 해보도록 하겠습니다.

```bash
$ mysqld-debug --debug=d,info,error,query,general,where:O,/tmp/mysqld.trace
```

참고: https://dev.mysql.com/doc/refman/5.7/en/making-trace-files.html

괘나 많은 로그가 떨어지겠지만.. 인덱스 있는 케이스와 없는 케이스 두 개로 나누어서 트레이스를 떠보면.. 대충 칼럼 사이즈 변경 시 **fill\_alter\_inplace_info 함수** 부분에서 리빌딩할 인덱스 리스트를 선별할 것 같은 우주의 기운이 팍팍 느껴지기 시작합니다. 왠지.. 동일 패딩 사이즈 경우 메타 정보를 수정해서 순식간에 ALTER 작업이 이루어지는 것처럼, 인덱스 리빌딩 단계에서 이 케이스를 선별해서 빼버린다면..?? 이런 병목은 사라질 것 같은 예감이 듭니다.

```plain
## 인덱스 없는 경우 ##
mysql_create_frm: info: wrote format section, length: 10
fill_alter_inplace_info: info: index count old: 0  new: 0

## 인덱스 있는 경우
fill_alter_inplace_info: info: index count old: 2  new: 2
fill_alter_inplace_info: info: index changed: 'ix_a_1'
fill_alter_inplace_info: info: index changed: 'ix_b_2'
```

다행히 이 문제는 MySQL 5.7.23 버전에서 픽스가 되었습니다. 소스를 살펴보고자, Oracle MySQL의 깃헙에 들어가서 살펴보던 중 왠지 우리와 비슷한 상황일 것 같은 커밋 코멘트(BUG#26848813: INDEXED COLUMN CAN'T BE CHANGED FROM VARCHAR(15))를 발견하였고, 대충 훑어보니 역시나 인덱스 리빌딩 케이스였더군요. (이렇게 절묘하게.. 손 안대고 코풀줄이야.. ㅋㅋ)  
참고: https://github.com/mysql/mysql-server/commit/913071c0b16cc03e703308250d795bc381627e37

5.7.23 버전에 online alter 플래그 중 `Alter_inplace_info::RENAME_INDEX` 비트 플래그를 하나 더 추가하였고, varchar 칼럼 확장이면서 패딩 사이즈가 동일하면 `Alter_inplace_info::RENAME_INDEX`로 분기 분류함으로써 인덱스를 리빌딩하지 않도록 제어하더군요. (부분부분 발췌합니다.)

```cpp
## fill_alter_inplace_info 함수 ###########
static bool fill_alter_inplace_info(THD *thd,
                                    TABLE *table,
                                    bool varchar,
                                    Alter_inplace_info *ha_alter_info)
{
  ....
  while ((rename_key= rename_key_it++))
  {
    ....
    if (! has_index_def_changed(ha_alter_info, table_key, new_key))
    {
      /* Key was not modified but still was renamed. */
      ha_alter_info->handler_flags|= Alter_inplace_info::RENAME_INDEX;
      ha_alter_info->add_renamed_key(table_key, new_key);
    }
    else
    {
      /* Key was modified. */
      ha_alter_info->add_modified_key(table_key, new_key);
    }
    ....
  }
  ....
}

## has_index_def_changed 함수 ###########
static bool has_index_def_changed(Alter_inplace_info *ha_alter_info,
                                  const KEY *table_key,
                                  const KEY *new_key)
{
    ....
    if (key_part->length != new_part->length &&
        ha_alter_info->alter_info->flags == Alter_info::ALTER_CHANGE_COLUMN &&
        (key_part->field->is_equal((Create_field *)new_field) == IS_EQUAL_PACK_LENGTH))
    {
      ha_alter_info->handler_flags|=
          Alter_inplace_info::ALTER_COLUMN_INDEX_LENGTH;
    }
    else if (key_part->length != new_part->length)
      return true;
    ....
}
```

아무튼 5.7.23에서는 이 코드 적용 결과.. 인덱스가 있을지라도 VARCHAR 칼럼 확장은 순식간에 바로 종료가 되는 쾌거를 이룹니다. 아직 5.7.23 이전 버전을 쓰고 계신 분들이 버전을 업그레이드 해야하는 또하나의 이유가 생겼네요. ㅋㅋ

# Conclusion

길고 긴.. 오늘 블로그 정리를 해보겠습니다. 그냥 이 세가지 이야기로 정리해보겠습니다.

1. **MySQL5.7.23 버전 이상으로 업그레이드 하는 것이 정신 건강에 좋다.**
2. **MySQL5.7.23 이전 버전 사용자들은, 칼럼에 인덱스가 걸려있는지 확인을 우선 해보고 작업 계획을 세운다.**
3. **무엇보다 매뉴얼은 매뉴얼일뿐, 맹신하지 말자.**

무엇보다 가장 알고 싶었던 부분은.. 매뉴얼과 전혀 다른 이 현상이 어디부터 시작된 이슈인지를 원인분석입니다. 이것을 알아야 이는 사이드이펙트를 최소화할 수 있는 우회방안도 고민해볼 수 있기 때문이죠. 피할 수 없으면 즐겨야할테니.. 맞더라도 이유는 알고 맞아야할 것이고.. 궁시렁궁시렁

저같은 C알못 평범남도 파보니 이해는 할 수 있겠드라고요. 엯촋들에게는 평범한 일상이겠지만.. 저같은 보통 사람들에게는 신성한 경험이었기에, 이를 공유 삼아 블로그 포스팅을 해봅니다.

아주 오랜만의 길고 긴 대하 소설.. 마칩니다. ㅋㅋ