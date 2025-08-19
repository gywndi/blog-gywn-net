---
title: MySQL 파티셔닝 테이블 SELECT가 느려요.
author: gywndi
type: post
date: 2019-08-29T14:56:26+00:00
url: 2019/08/mysql-poor-performance-with-super-many-partitions
categories:
  - MariaDB
  - MySQL
tags:
  - MySQL
  - partition
  - Performance

---
# Overview

네이티브 파티셔닝 적용 이전의 MySQL은, 파티셔닝 파일들은 각각이 테이블로써 관리되었죠. 그래서, table cache 로 인한 메모리 부족 현상은 인지하고 있었습니다만.. 이것 외에는 특별히 성능 저하 요소는 없다고 생각해왔어요. (http://small-dbtalk.blogspot.com/2013/09/mysql-table-cache.html)

그런데, 얼마전 서버당 4개의 데이터베이스를 만들고, 각각 데이터베이스 안에 26개월로 분할된 파티셔닝된 테이블을 넣고, 간단한 Range scan 성능 테스트를 하였는데.. 말도안되는 수치를 보였습니다. 이 관련하여 간단하게 이에 대해 알아보도록 할께요. 🙂

# Problem

하단과 같은 테이블 구조에서, 단순히 최근 10건의 데이터만 끌어오는 형식의 SQL을 다수 실행시켜 간단한 트래픽을 주었을 때.. 성능적으로 별다른 문제는 없을 것이라고 생각을 했습니다. 우리의 메모리는 기대치보다 훨씬 웃돌았기 때문에.. ㅎㅎ (참고로, InnoDB 버퍼풀 사이즈 대비 데이터 사이즈는 약 10배 이상이지만, 최근 파티셔닝 사이즈를 따지면, 버퍼풀 안에 충분히 들어올만한 상황이었습니다.)

```sql
## table
CREATE TABLE `tab` (
`COL01` varchar(16) COLLATE utf8mb4_bin NOT NULL,
`PAR_DATE` varchar(8) COLLATE utf8mb4_bin NOT NULL,
`COL02` decimal(10,0) NOT NULL,
`COL03` decimal(10,0) NOT NULL,
.. skip ..
`APLY_TMST2` timestamp(3) NOT NULL,
PRIMARY KEY (`COL01`,`PAR_DATE`,`COL02`,`COL03`),
) ENGINE=InnoDB
PARTITION BY RANGE COLUMNS(PAR_DATE)
(PARTITION PF_201707 VALUES LESS THAN ('20170801') ENGINE = InnoDB,
 PARTITION PF_201708 VALUES LESS THAN ('20170901') ENGINE = InnoDB,
 .. skip ..
 PARTITION PF_201907 VALUES LESS THAN ('20190801') ENGINE = InnoDB,
 PARTITION PF_201908 VALUES LESS THAN ('20190901') ENGINE = InnoDB);

## Query
select * from tab
where col01 = ?
order by par_date desc, col02 desc, col03 desc
limit 10
```

그러나.. 예상과는 다르게, 말도안되는 퍼포먼스와, 이상한 IO패턴을 보이는 결과를 보였죠.

# Why?

결론부터 이야기를 하자면, InnoDB. 파티셔닝에서.. 실행계획을 세우는 단계에서 모든 파티션에 약 1~3개 정도의 페이지를 읽게되는데.. 이런 동작으로 인하여 엄청난 비효율이 발생하고 마는 것이죠. 모든 파티션에 해당하는 블록들이 InnoDB 버퍼풀에 올라와있지 않기 때문이죠. (실제로 메모리에 존재할지라도, 쿼리당 수십개의 페이지에 접근한다는 것 역시도 부하라고 생각합니다.)

실행계획 단계의 요 부분에서, 불필요하게 파티셔닝을 접근을 시도해서, 이런 비효율을 발생시키는데요

```cpp
for (part_id = m_part_info > get_next_used_partition(part_id);
     part_id < m_tot_parts;
     part_id = m_part_info > get_next_used_partition(part_id)) {
  index = m_part_share > get_index(part_id, keynr);
  // .. skip ..
  int64_t n = btr_estimate_n_rows_in_range(index, range_start, mode1,
                                           range_end, mode2);
  n_rows += n;
  DBUG_PRINT("info", ("part_id %u rows %ld (%ld)", part_id, (long int)n,
                      (long int)n_rows));
}
```

출처: https://github.com/mysql/mysql-server/blob/4869291f7ee258e136ef03f5a50135fe7329ffb9/storage/innobase/handler/ha_innopart.cc#L3281

사실, 이렇게 대략적인 데이터 건 수를 판단한 후 일부 파티셔닝에 접근할 필요없이, 모든 파티셔닝에 데이터가 존재한다는 가정으로 데이터에 접근을 해도 큰 무리없다고 생각이 마구마구 드는 시점이네요.

# Solution

사실 당장의 솔루션은 없습니다. 그냥, 파티셔닝 수를 최소화하는 수밖에 없답니다. 미네랄..ㅜㅜ

단, Percona MySQL경우에는 하단과 같이 추가 파라메터(`force_index_records_in_range`, `records_in_range`)를 추가하여, 해당 테이블에 데이터가 특정 건수(할당한 파라메터값)으로 지정을 함으로써 전체 파티셔닝에 접근하지 않도록 우회할 수 있는데요. (이렇게 유도하기까지 꽤나 어려웠어요.ㅠㅠ)

깃헙: https://github.com/dutow/percona-server/commit/677aa7c8aa64ca0aca25c07813e48309e5f06109

이렇게 소스를 변경해서, 테스트트를 해본 결과 놀라운 성능 변화가 있었습니다.

이런 말도 안되는 성능을 보였던 녀석이!!

```sql
set records_in_range = 0;
set force_index_records_in_range = 0;
=============================
Device: r/s rkB/s %util
disk01 28364.00 453824.00 100.00
disk01 29050.00 464800.00 99.80
disk01 31827.00 509232.00 99.90
disk01 29660.00 474560.00 99.40
disk01 31570.00 505120.00 99.90

time opr ms/opr
11:31:18 4553 11.01
11:31:19 4639 10.76
11:31:20 4581 10.86
```

단 몇줄 수정만으로도, 이런 성능 수치를 보였답니다. 대충 봐도 4배정도 향상이 이루어졌습니다, ㅎㅎ (4500 qps vs 17000 qps)

```sql
set records_in_range = 1000;
set force_index_records_in_range = 1000;
=============================
Device: r/s rkB/s %util
disk01 24930.00 398896.00 96.70
disk01 25671.00 410720.00 97.10
disk01 24245.00 387920.00 96.90
disk01 24938.00 399008.00 97.10
disk01 25155.00 402480.00 97.10

time opr ms/opr
11:36:48 17156 2.89
11:36:49 16873 2.94
11:36:50 16965 2.92
```

이 픽스는 다음번 GA 릴리즈 버전에 포함되어서 나오게 될 예정이고.. 동시에 Oracle 커뮤니티 버그 사이트에서 진행하던 동일 이슈도 나름 긍정적인 형태로 진행 중에 있는 듯 하군요.

관련 : https://bugs.mysql.com/bug.php?id=96233

# Conclusion

엄청난 갯수의 파티셔닝을 가진 상황에서, 이상하게 쿼리가 느린 것을 경험하신 분들! 파티셔닝 테이블 조회 시 이와 같은 이슈로 리소스가 충분히 활용되고 있지 않은지를 한번쯤 확인을 해보세요. ㅎㅎ 어서어서 오라클에서도 관련된 픽스가 이루어져서, 이런 비효율이 없어지기를 빌어봅니다. ㅋ

간만에 끄적인 블로그를 너무 서술한듯한 느낌이네요. (오늘 ifkakao 발표 후인지라.. 피곤..ㅠㅜ) 이 다음부터는 더욱 재미난 내용을 붙이도록 하겠습니다. 꾸벅.