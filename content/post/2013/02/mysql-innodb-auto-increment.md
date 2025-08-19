---
title: InnoDB에서 Auto_Increment를 맹신하지 말자.
author: gywndi
type: post
date: 2013-02-17T15:01:55+00:00
url: 2013/02/mysql-innodb-auto-increment
categories:
  - MariaDB
  - MySQL
tags:
  - Auto Increment
  - MySQL

---
# Overview

MySQL에서는 시퀀스 개념이 없지만, 테이블 단위로 움직이는 Auto\_Increment라는 강력한 기능이 있습니다. Auto\_Increment 속성은 숫자 형 Primary Key를 생성하는 데 많이 사용됩니다.

특히나 InnoDB 경우에는 Primary Key 사이즈가 전체 인덱스 사이즈에 직접적인 영향을 미치기 때문에, 저도 테이블 설계에 많이 권고하는 사항이기도 합니다.

그러나 InnoDB에서 Auto_Increment가 동작하는 방식을 정확하게 알지 못하고 사용하면, 대형 장애 상황으로도 치닫을 수 있습니다.

오늘은 간단한 사례를 바탕으로 관련 내용을 공유할까 합니다. ^^

# Auto_Increment In InnoDB

Auto\_Increment는 스토리지 엔진 별로 다르게 동작합니다. 파일 기반의 스토리지 엔진인 MyISAM 경우에는 현재 Auto\_Increment값이 파일에 일일이 기록되는 방식으로 관리됩니다. 그러나 메모리 기반의 스토리지 엔진인 InnoDB에서는 조금 다른 방식으로 관리됩니다.

InnoDB에서는 MyISAM과는 다르게 Auto_Increment 값이 변경될 때마다 기록하지 않습니다. &#8220;**메모리 상에서 Auto_Increment 값을 관리&#8221;**하는 것이죠. DB가 처움 구동되면 다음과 같이 Auto_Increment 속성이 있는 테이블은 모두 초기화됩니다.

```sql
SELECT MAX(ai_col) FROM t for UPDATE
```

만약 결과 값이 NULL이면 Auto\_Increment\_Offset으로 대체되거나, 1로 초기화됩니다. 그리고 Auto\_Increment\_Increment만큼 증가되어 Auto_Increment 가 관리되는 것이죠. 이런 상황에서 어떤 문제가 발생할 수 있을까요?

# Problem Case

인지하고 있어야 하는 부분은 바로 위에서 Auto\_Increment값이 초기화되는 부분입니다. 각 테이블의 Auto\_Increment값을 최대값을 기준으로 초기화하기 때문에, 서버 재시작 시 올바른 Auto_Increment 값이 설정되지 않을 가능성이 있는 것입니다.

그렇다면 테스트를 해볼까요? 다음과 같이 테이블을 생성합니다.

```sql
CREATE TABLE `test` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `j` char(1) DEFAULT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
```

그리고 10 건의 데이터를 넣고, 현재 Auto_Increment 값을 확인해봅니다.

```sql
## 10건 데이터 Insert
mysql> insert into test (j) values ('1');

## 테이블 스키마 조회
mysql> show create table test\G
CREATE TABLE `test` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `j` char(1) DEFAULT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8
```

이 상황에서 모든 데이터를 지우고 다시 한번 Auto_Increment값을 확인해봅니다.

```sql
mysql> delete from test;
Query OK, 10 rows affected (0.00 sec)

## 테이블 스키마
mysql> show create table test\G
CREATE TABLE `test` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `j` char(1) DEFAULT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8
```

여전히 Auto_Increment 값은 11로 변동이 없습니다.

그렇다면 여기서 DB를 재시작 후 확인해보면 어떨까요? DB를 재시작 후 다시 한번 스키마를 확인해 봅니다.

```sql
CREATE TABLE `test` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `j` char(1) DEFAULT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
```

분명 11로 설정되어 있어야할 값이 마치 테이블이 처음 생성된 것처럼 조회가 됩니다. 이 상태에서 한 건의 데이터를 넣고 다시 한번 테이블 스키마를 확인해 봅니다.

```sql
mysql> insert into test (j) values ('1');

mysql> show create table test\G
CREATE TABLE `test` (
  `i` int(11) NOT NULL AUTO_INCREMENT,
  `j` char(1) DEFAULT NULL,
  PRIMARY KEY (`i`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8
```

Auto_Increment 값이 11에서 2로 변경되는 어이없는 현상이 발생했습니다. 이 같은 현상은 파일 기반 스토리지 엔진인 MyISAM에서는 발생하지 않습니다. 비록 Delete가 된다고 하더라도 그 값은 디스크에 기록을 하기 때문이죠.

# Conclusion

MyISAM테이블을 성능 및 안정성 이슈로 InnoDB로 전환 후 서버 재시작 시 매번 Primary Key 중복 오류가 발생한 사례가 있습니다. 결과적으로 Delete 스케줄링이 문제가 되었고, 관련 로직을 제거함으로써 해결하게 되었죠. Auto_Increment의 가장 최근 데이터를 삭제 처리하는 로직만 없다면 아~무런 문제가 없습니다.

InnoDB에서 Auto_Increment를 사용하고 있다면 이와 같은 특성을 반드시 이해하고 예기치 않는 장애 사항을 사전에 예방하시기 바랍니다. ^^

이직 후 적응 기간을 거쳐 오랜만에 포스팅 합니다. ^^

감사합니다.