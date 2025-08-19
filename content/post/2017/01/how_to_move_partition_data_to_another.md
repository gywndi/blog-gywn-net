---
title: MySQL에서 파티션 일부를 다른 파티션 테이블로 옮겨보기
author: gywndi
type: post
date: 2017-01-20T04:24:56+00:00
url: 2017/01/how_to_move_partition_data_to_another
categories:
  - MySQL
  - Research
tags:
  - MySQL
  - partition

---
# Overview

한동안 운영에 치여, 문서를 못봤더니, 재미난 사례를 많이 놓친듯.  
그래서 여기저기 떠도는 문서 중 재미난 사례 하나를 내 입맛에 맞게 샘플을 변경해서 공유해봅니다.  
(영혼없이 붙여넣기만 해도 알아보기 쉽게 ㅋㅋ)

# Preview

파티셔닝 특정 부분을 다른 테이블 혹은 파티셔닝 일부로 넘기는 방안에 대한 것인데..

![move-partition-data-file](/img/2017/01/move-partition-data-file.png)

하단 포스팅 내용 중 미흡한 부분을 보완해서 정리해본 것입니다  
https://dzone.com/articles/how-to-move-a-mysql-partition-from-one-table-to-an

# Generate Test Data

먼저 테스트 데이터를 생성해야할테니..

```sql
mysql> create table f_tb (
      seq bigint(20) not null default '0',
      regdate date not null,
      cont text not null,
      primary key (seq,regdate)
  ) engine=innodb collate=utf8_unicode_ci
  /*!50500 partition by range columns(regdate)
  (partition p09 values less than ('2016-10-01'),
   partition p10 values less than ('2016-11-01'),
   partition p11 values less than ('2016-12-01'),
   partition p12 values less than ('2017-01-01')) */;
```

아래처럼 테스트로 사용할 데이터를 간단하게 생성해봅니다. 2017-01-01 기점으로 랜덤하게 120일 사이 일을 빼서 마치 파티셔닝 테이블이 관리된 것처럼 데이터를 밀어넣는 것이죠.

```sql
## 1건 데이터 생성
mysql> insert ignore into f_tb values
    (rand()*1000000000, date_sub('2017-01-01', interval rand()*120 day), repeat(uuid(),5));

## 원하는 만큼 반복 수행
mysql> insert ignore into f_tb
  select rand()*1000000000,
      date_sub('2017-01-01',
      interval rand()*120 day), repeat(uuid(),5)
  from f_tb;
```

위에서 만든 이후 실제 테이블 데이터 건 수를 보면.. (전 대략 8000건만 만들었어요. 귀찮아서. ㅋ)

```sql
mysql> select count(*) from f_tb;
+----------+
| count(*) |
+----------+
|     8064 |
+----------+
```

# Move Datafile to Temporay Table

자~ 이제 특정 파티셔닝 파일을 다릍 파티셔닝의 일부로 옮기는 작업을 해볼까요.

### 1) 동일한 테이블을 만들고, 파티셔닝이 없는 일반 테이블로 구성한다.

```sql
mysql> create table f_tb_p09 like f_tb;
mysql> alter table f_tb_p09 remove partitioning;
```

### 2) 임시 테이블 discard처리

f_tb에서 9월 데이터를 가져오기 위해, 테이블스페이스에서 discard 하도록 수행합니다. 임시 깡통 데이터가 사라지겠지요.

```sql
mysql> alter table f_tb_p09 discard tablespace;
```

### 3) 테이블 데이터 복사

파일 복사 이전에, 원본 테이블에 export를 위한 락을 걸고, 데이터 카피 후 락을 풀어줍니다.  
(두개 세션 열기 귀찮으니.. MySQL 콘솔 클라이언트에서 바로 파일을 복사하도록.. ㅋㅋ)

```sql
mysql> flush table f_tb for export;
mysql> \! cp /data/mysql/test_db/f_tb#p#p09.ibd /data/mysql/test_db/f_tb_p09.ibd
mysql> unlock tables;
```

### 4) 임시 테이블에 데이터파일 Import

옮겨온 데이터파일을 실제 임시로 생성한 테이블에서 읽을 수 있도록 import 처리 해줍니다.

```sql
mysql> alter table f_tb_p09 import tablespace;
```

자~ 이제 정상적으로 데이터가 잘 옮겨졌는지 카운트를 해볼까요?

```sql
mysql> select count(*) from f_tb_p09;
+----------+
| count(*) |
+----------+
|     1860 |
+----------+
```

굳~ 잘 되었네요.

# Import to archive

아카이브 테이블이 없다는 가정하에.. 아래와 같이 타겟 파티셔닝 테이블을 생성합니다. 당연한 이야기겠지만, 파티셔닝 정의를 제외한 테이블 구조는 동일해야하겠지요?

```sql
mysql> create table t_tb (
      seq bigint(20) not null default '0',
      regdate date not null,
      cont text not null,
      primary key (seq,regdate)
  ) engine=innodb collate=utf8_unicode_ci
  /*!50500 partition by range columns(regdate)
  (partition p09 values less than ('2016-10-01'),
   partition p10 values less than ('2016-11-01')) */;

mysql> select count(*) from t_tb;
+----------+
| count(*) |
+----------+
|        0 |
+----------+
```

자~ 끝판왕.. 마지막으로.. 타겟 파티셔닝 파일에 데이터파일을 변경해준다는 하단 alter 구문만 날려주면 끝~

```sql
mysql> alter table t_tb exchange partition p09 with table f_tb_p09;

mysql> select count(*) from t_tb;
+----------+
| count(*) |
+----------+
|     1860 |
+----------+
```

중요치는 않지만.. 임시 테이블 데이터는 깡통으로 남지요.  
(COPY가 아닙니다. 임시 테이블에 데이터는 사라져요. ㅋ)

```sql
mysql> select count(*) from f_tb_p09;
+----------+
| count(*) |
+----------+
|        0 |
+----------+
```

# Conclusion

신기하기는 했지만.. 이걸 어디에 쓸 수 있을까 잠깐 생각을 해봤는데.. 대고객 온라인 서비스에서는 큰 의미는 없다고 생각되는데요.

MySQL의 가장 큰 강점은 개인적으로 **데이터 복제**라고 생각합니다. Replication.. 그러나.. 위와 같이 데이터파일을 옮긴다면.. 아무래도 OS 상에서 동작하기에.. 데이터 복제 개념과는 동떨어진 처리입니다. 즉.. 설혹 마스터에서 특정 테이블 일부 데이터를 다른 테이블의 일부로 옮겨놓아도, 실제 슬레이브에서는 이 명령이 그대로 적용되지 않음을 의미하죠.

그러나!

만약 **특정 테이블에 대한 데이터 분석 혹은 보관과 같은 이슈**가 있을 시.. 덤프 없이, 놀고 있는 슬레이브, 혹은 스탠바이, 장비에서 일시적으로 잠금 처리를 한 후 파일 단위로 빠르게 옮겨봄으로써 의외로 쉽게 대응이 가능합니다. 물로 반드시 파티셔닝 테이블에 포함해야할 필요는 없지만.. ^^ 어플리케이션 복잡도를 줄이기 위해서라면 위와 같이 파티셔닝 테이블의 일부로 적용하는 것도 좋은 케이스이겠고요.

감사합니다. ^^