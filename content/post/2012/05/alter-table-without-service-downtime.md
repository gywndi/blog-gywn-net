---
title: MySQL에서 테이블 스키마를 “무중단”으로 변경해보자!!
author: gywndi
type: post
date: 2012-05-22T09:47:10+00:00
url: 2012/05/alter-table-without-service-downtime
categories:
  - MySQL
tags:
  - Alter Table
  - Migration
  - MySQL

---
# Overview {#MySQLIsolationLevel에따른SQL사용주의사항-Overview}

MySQL은 단순 쿼리 처리 능력은 탁월하나 테이블 스키마 변경 시에는 상당히 불편합니다. 일단 테이블 스키마 변경 구문을 실행하면 임시 테이블 생성 후 데이터를 복사하고, 데이터를 복사하는 동안에는 테이블에 READ Lock이 발생하여 데이터 변경 작업을 수행하지 못합니다. (Table Lock이 걸리죠.)

이 같은 현상은 인덱스, 칼럼 추가/삭제 뿐만 아니라 캐릭터셋 변경 시에도 동일하게 발생합니다. (최근 5.5 버전에서는 인덱스 추가/삭제에서는 임시 테이블을 생성하지 않습니다.)

얼마 전 서비스 요구 사항 중 테이블 칼럼을 무중단으로 변경하는 것이 있었는데, 이에 관해 정리 드리겠습니다.^^

# 요구사항

서비스 요구사항과 개인적인 요구 사항은 다음과 같습니다.

  1. **최대한 서비스 중단 없이 가능해야 함**
  2. **테이블에 Lock이 발생하지 말아야 함**
  3. **빠르게 구현해야 함(개인 요구 사항)**
  4. **재사용 가능해야 함(개인 요구 사항)**
  5. **문제 발생 시 복구가 쉬워야 함**

개인적으로 빠르게 적용하는 것과 이와 같은 이슈가 추후 재 발생 시 재사용할 수 있도록 모듈화하자는 것이 목표였습니다.

# 대상 테이블 분석

대상 테이블은 다음과 같은 특징이 있었습니다.

  1. **Auto_increment 옵션이 적용되었으며, Primary Key가 존재함**
  2. **데이터 변경에는 Insert와 Delete만 발생(Update 없음)**
  3. **연관된 프로시저 및 트리거는 없음**

무엇보다 Update가 없기 때문에 조금 더 생각을 심플하게 가져갈 수 있었습니다.

# 작업 시나리오

![How to migrate data to different table](/img/2012/05/how_to_migrate_data1.png)

트리거로 기존 테이블에 Insert및 Delete 시 변경 분을 별도 테이블에 저장을 합니다. 그리고 임시 테이블을 만들고 해당 테이블에 기존 테이블 데이터를 이관합니다. 물론 임시 테이블에는 원하는 스키마로 변경된 상태겠죠. Import가 마무리되면 트리거에 쌓인 데이터로 변경 분을 적용하고 최종적으로 테이블을 Rename함으로써 프로세스가 마무리됩니다.

조금더 상세하게 풀자면 다음과 같습니다.

  1. **임시 테이블 생성** 
      * Insert/Delete 시 변경 사항을 저장할 테이블  
        (TAB01\_INSERT, TAB01\_DELETE)
      * 데이터를 임시로 저장할 테이블
  2. **트리거 생성** 
      * 원본 테이블에 Delete 발생 시 해당 ROW를 임시 테이블에 저장
      * 원본 테이블에 Insert 발생 시 해당 ROW를 임시 테이블에 저장
  3. **원본 테이블 export/import** 
      * export -> 테이블명 변경 -> import
      * SED로 테이블 명을 임시 테이블 명으로 변경
  4. **원본 테이블과 임시 테이블 RENAME** 
      * 원본 테이블 : TAB01 -> TAB01_OLD
      * 임시 테이블 : TAB01_TMP -> TAB01
  5. **테이블 변경 분 저장** 
      * TAB01_INSERT에 저장된 데이터 Insert
      * TAB01_DELETE에 저장된 데이터 Delete
  6. **트리거, 임시테이블 제거** 
      * 트리거 : Insert트리거, Delete 트리거
      * 테이블 : TAB01\_INSERT, TAB01\_DELETE

모든 작업을 어느정도 자동화 구현하기 위해 `작업 스크립트&#8221;를 만드는 프로시저와 데이터 이관을 위한 She를 작성하였습니다.

Shell 스크립트는 Export와 동시에 SED 명령을 통해 자동으로 테이블 이름을 변경하여 Import하도록 구현하였습니다.

DB명, 테이블명,  스키마 변경 내용을 다음과 같이 인자 값으로 넘겨서 프로시저를 호출합니다.  
(프로시저 소스는 가장 하단 참조)

```sql
call print_rb_query('dbatest', 'TAB01', 'MODIFY ACT_DESC VARCHAR(100) CHARACTER SET UTF8MB4 COLLATE UTF8MB4_UNICODE_CI DEFAULT NULL;');
```

그러면 아래와 같이 결과가 나오는데 Step1, 2, 3을 순차적으로 실행하면 됩니다. 보기 쉽게 주석을 추가하겠습니다.^^

```sql
>> Step 1>  Prepare : SQL &lt;&lt;
## 임시 테이블 생성
DROP TABLE IF EXISTS dbatest.TAB01_INSERT;
CREATE TABLE dbatest.TAB01_INSERT LIKE TAB01;
DROP TABLE IF EXISTS dbatest.TAB01_DELETE;
CREATE TABLE dbatest.TAB01_DELETE LIKE TAB01;
DROP TABLE IF EXISTS dbatest.TAB01_TMP;
CREATE TABLE dbatest.TAB01_TMP LIKE TAB01;

## 임시 테이블 스키마 변경
ALTER TABLE dbatest.TAB01_TMP AUTO_INCREMENT = 10660382;
ALTER TABLE dbatest.TAB01_TMP MODIFY ACT_DESC VARCHAR(100) CHARACTER SET UTF8MB4 COLLATE UTF8MB4_UNICODE_CI DEFAULT NULL;
DELIMITER $$

## Delete 트리거 생성
DROP TRIGGER IF EXISTS dbatest.TRG_TAB01_DELETE$$
CREATE TRIGGER dbatest.TRG_TAB01_DELETE
AFTER DELETE ON dbatest.TAB01
FOR EACH ROW
BEGIN
INSERT INTO dbatest.TAB01_DELETE VALUES(
    OLD.ACT_ID,
    OLD.ACT_UID,
    OLD.ACT_USER_NAME,
    OLD.ACT_TIME,
    OLD.TO_UID,
    OLD.TO_USER_NAME,
    OLD.ACT_TYPE,
    OLD.POSTID,
    OLD.TAB01,
    OLD.ACT_DESC,
    OLD.BEFORE_USER_NAME,
    OLD.PHOTO_LINK,
    OLD.THUMB_URL,
    OLD.FROM_SERVICE);
END$$

## Insert 트리거 생성
DROP TRIGGER IF EXISTS dbatest.TRG_TAB01_INSERT$$
CREATE TRIGGER dbatest.TRG_TAB01_INSERT
AFTER INSERT ON dbatest.TAB01
FOR EACH ROW
BEGIN
INSERT INTO dbatest.TAB01_INSERT VALUES(
    NEW.ACT_ID,
    NEW.ACT_UID,
    NEW.ACT_USER_NAME,
    NEW.ACT_TIME,
    NEW.TO_UID,
    NEW.TO_USER_NAME,
    NEW.ACT_TYPE,
    NEW.POSTID,
    NEW.TAB01,
    NEW.ACT_DESC,
    NEW.BEFORE_USER_NAME,
    NEW.PHOTO_LINK,
    NEW.THUMB_URL,
    NEW.FROM_SERVICE);
END$$
DELIMITER ;

>> Step 2>  Data Copy : Shell Script &lt;&lt;
## 데이터 마이그레이션
mig_dif_tab.sh dbatest TAB01 TAB01_TMP

>> Step 3>  Final Job : SQL &lt;&lt;
## 변경분 적용
INSERT INTO dbatest.TAB01_TMP SELECT * FROM dbatest.TAB01_INSERT;
DELETE A FROM dbatest.TAB01_TMP A INNER JOIN dbatest.TAB01_DELETE B ON A.ACT_ID = B.ACT_ID;

## 테이블 Rename(Swap)
RENAME TABLE dbatest.TAB01 TO dbatest.TAB01_OLD, dbatest.TAB01_TMP TO dbatest.TAB01;

## 트리거 제거
DROP TRIGGER IF EXISTS dbatest.TRG_TAB01_DELETE;
DROP TRIGGER IF EXISTS dbatest.TRG_TAB01_INSERT;

##변경분 재 적용 (확인 사살)
INSERT INTO dbatest.TAB01 SELECT * FROM dbatest.TAB01_INSERT;
DELETE A FROM dbatest.TAB01 A INNER JOIN dbatest.TAB01_DELETE B ON A.ACT_ID = B.ACT_ID;

## 임시 테이블 제거
DROP TABLE IF EXISTS dbatest.TAB01_INSERT;
DROP TABLE IF EXISTS dbatest.TAB01_DELETE;
```

임시 테이블에는 Auto_increment 값을 **기존보다 1% 높게 설정**하여 테이블명 Swap 후 Primary Key 충돌이 없도록 하였습니다. 그리고 Insert ignore문을 사용하여 Primary Key 중복으로 발생하는 오류는 무시하도록 하였고, 테이블 Rename 후 변경분을 재 적용하는 확인사살도 하였습니다. ^^;;

### Shell 스크립트

위에서 Step2에서 사용하는 Shell 스크립트는 다음과 같습니다.

```sql
#!/bin/sh
if [ $# -ne 3 ]; then
echo "Usage: ${0} &lt;Database_Name> &lt;Orignal_Table> &lt;Target_Table>"
echo "&lt;Example>"
echo "Database Name : snsdb"
echo "Orignal Table : tab01"
echo "Target Table  : tab01_tmp"
echo "==> ${0} snsdb tab01 tab01_tmp"
exit 1
fi
## Declare Connection Info
export DB_CONNECT_INFO="-u계정 -p패스워드"
export REMOTE_DB_HOST="DB호스트URL"
export REMOTE_DB_PORT="3306"

## Exec profile for mysql user
. ~/.bash_profile

## Dump and Insert Data
mysqldump ${DB_CONNECT_INFO}                           \
  --single-transaction                                 \
  --no-create-db                                       \
  --no-create-info                                     \
  --triggers=false                                     \
  --comments=false                                     \
  --add-locks=false                                    \
  --disable-keys=false                                 \
  --host=${REMOTE_DB_HOST}                             \
  --port=${REMOTE_DB_PORT}                             \
  --databases ${1}                                     \
  --tables ${2}                                        \
| sed -r 's/^INSERT INTO `'${2}'`/INSERT INTO `'${3}'`/gi' \
| mysql ${DB_CONNECT_INFO} -h ${REMOTE_DB_HOST} -P ${REMOTE_DB_PORT} ${1}
```

Export 값을 파이프(|)로 sed로 넘기고, sed에서는 테이블명만 정규식으로 바꿔서 최종적으로 Import하는 구문입니다.

`Create Table As Select` 혹은 `Insert into Select` 구문을 사용하지 않은 이유는 **Redo 로그가 비대해짐에 따라 시스템 부하**가 따르기 때문입니다. tx_isolation 값을 READ-COMMITTED로 설정하여도 데이터가 전체 들어간 시점에 **일시적인 테이블 Lock이 발생**합니다. (트랜잭션을 마무리하는 과정에서 발생하는 Lock입니다.) [MySQL 트랜잭션 IsoLevel로 인한 장애 사전 예방 법](/2012/05/mysql-transaction-isolation-level) 을 참고하세요.^^

### 프로시저

단일 테이블이라면 위에 있는 스크립트를 약간만 수정하면 되겠지만, 제 경우는 변경할 테이블이 꽤 많아서 스크립트를 생성하는 프로시저를 아래와 같이 구현하였습니다.

사실 모든 과정을 Perl 혹은 Java로 구현하면 Step없이 간단했겠지만, DB 접속 서버에 구성하기 위해서는 절차 상 복잡한 부분이 있어서 프로시저로 작성하였습니다. ㅎㅎ

```sql
DELIMITER $$
DROP PROCEDURE print_rb_query $$
CREATE PROCEDURE print_rb_query(IN P_DB VARCHAR(255), IN P_TAB VARCHAR(255), IN P_ALTER_STR VARCHAR(1024))
BEGIN
    ## Declare Variables
    SET @qry = '\n';
    SET @ai_num = 0;
    SET @ai_name = '';
    SET @col_list = '';

    ## Get AUTO_INCREMENT Number for Temporary Table
    SELECT CAST(AUTO_INCREMENT*1.01 AS UNSIGNED) INTO @ai_num
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = P_DB
    AND TABLE_NAME = P_TAB;

    ## Get auto_increment Column Name
    SELECT COLUMN_NAME INTO @ai_name
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = P_DB
    AND TABLE_NAME = P_TAB
    AND EXTRA = 'auto_increment';

    SET @qry = CONCAT(@qry, '>> Step 1>  Prepare : SQL &lt;&lt;\n');
    SET @qry = CONCAT(@qry, 'DROP TABLE IF EXISTS ',P_DB,'.',P_TAB,'_INSERT;\n');
    SET @qry = CONCAT(@qry, 'CREATE TABLE ',P_DB,'.',P_TAB,'_INSERT LIKE ',P_TAB,';\n');
    SET @qry = CONCAT(@qry, 'DROP TABLE IF EXISTS ',P_DB,'.',P_TAB,'_DELETE;\n');
    SET @qry = CONCAT(@qry, 'CREATE TABLE ',P_DB,'.',P_TAB,'_DELETE LIKE ',P_TAB,';\n');
    SET @qry = CONCAT(@qry, 'DROP TABLE IF EXISTS ',P_DB,'.',P_TAB,'_TMP;\n');
    SET @qry = CONCAT(@qry, 'CREATE TABLE ',P_DB,'.',P_TAB,'_TMP LIKE ',P_TAB,';\n');
    SET @qry = CONCAT(@qry, 'ALTER TABLE ',P_DB,'.',P_TAB,'_TMP AUTO_INCREMENT = ',@ai_num,';\n');
    SET @qry = CONCAT(@qry, 'ALTER TABLE ',P_DB,'.',P_TAB,'_TMP ',P_ALTER_STR,'\n');

    ## Change Delimiter
    SET @qry = CONCAT(@qry, 'DELIMITER $$\n');

    ## Get Column List for Delete Trigger
    select GROUP_CONCAT('\n    OLD.',COLUMN_NAME) into @col_list
    from INFORMATION_SCHEMA.COLUMNS
    where TABLE_SCHEMA = P_DB
    and table_name = P_TAB
    order by ORDINAL_POSITION;

    SET @qry = CONCAT(@qry, 'DROP TRIGGER IF EXISTS ',P_DB,'.TRG_',P_TAB,'_DELETE$$\n');
    SET @qry = CONCAT(@qry, 'CREATE TRIGGER ',P_DB,'.TRG_',P_TAB,'_DELETE\n');
    SET @qry = CONCAT(@qry, 'AFTER DELETE ON ',P_DB,'.',P_TAB,'\n');
    SET @qry = CONCAT(@qry, 'FOR EACH ROW\n');
    SET @qry = CONCAT(@qry, 'BEGIN\n');
    SET @qry = CONCAT(@qry, 'INSERT INTO ',P_DB,'.',P_TAB,'_DELETE VALUES(');
    SET @qry = CONCAT(@qry, @col_list);
    SET @qry = CONCAT(@qry, ');\n');
    SET @qry = CONCAT(@qry, 'END$$\n');

    ## Get Column List for Insert Trigger
    select GROUP_CONCAT('\n    NEW.',COLUMN_NAME) into @col_list
    from INFORMATION_SCHEMA.COLUMNS
    where TABLE_SCHEMA = P_DB
    and table_name = P_TAB
    order by ORDINAL_POSITION;
    SET @qry = CONCAT(@qry, 'DROP TRIGGER IF EXISTS ',P_DB,'.TRG_',P_TAB,'_INSERT$$\n');
    SET @qry = CONCAT(@qry, 'CREATE TRIGGER ',P_DB,'.TRG_',P_TAB,'_INSERT\n');
    SET @qry = CONCAT(@qry, 'AFTER INSERT ON ',P_DB,'.',P_TAB,'\n');
    SET @qry = CONCAT(@qry, 'FOR EACH ROW\n');
    SET @qry = CONCAT(@qry, 'BEGIN\n');
    SET @qry = CONCAT(@qry, 'INSERT INTO ',P_DB,'.',P_TAB,'_INSERT VALUES(');
    SET @qry = CONCAT(@qry, @col_list);
    SET @qry = CONCAT(@qry, ');\n');
    SET @qry = CONCAT(@qry, 'END$$\n');

    ## Change Delimiter
    SET @qry = CONCAT(@qry, 'DELIMITER ;\n');
    SET @qry = CONCAT(@qry, '\n\n');

    ## Insert Data
    SET @qry = CONCAT(@qry, '>> Step 2>  Data Copy : Shell Script &lt;&lt;\n');
    SET @qry = CONCAT(@qry, 'mig_dif_tab.sh ',P_DB,' ',P_TAB,' ',P_TAB,'_TMP\n');
    SET @qry = CONCAT(@qry, '\n\n');
    SET @qry = CONCAT(@qry, '>> Step 3>  Final Job : SQL &lt;&lt;\n');

    ## Insert Data into Temporary Table
    SET @qry = CONCAT(@qry, 'INSERT IGNORE INTO ',P_DB,'.',P_TAB,'_TMP SELECT * FROM ',P_DB,'.',P_TAB,'_INSERT;\n');

    ## Delete Data from Temporary Table
    SET @qry = CONCAT(@qry, 'DELETE A FROM ',P_DB,'.',P_TAB,'_TMP A INNER JOIN ',P_DB,'.',P_TAB,'_DELETE B ON A.',@ai_name,' = B.',@ai_name,';\n');

    ## Swap table names
    SET @qry = CONCAT(@qry, 'RENAME TABLE ',P_DB,'.',P_TAB,' TO ',P_DB,'.',P_TAB,'_OLD, ',P_DB,'.',P_TAB,'_TMP TO ',P_DB,'.',P_TAB,';\n');

    ## Drop Triggers
    SET @qry = CONCAT(@qry, 'DROP TRIGGER IF EXISTS ',P_DB,'.TRG_',P_TAB,'_DELETE;\n');
    SET @qry = CONCAT(@qry, 'DROP TRIGGER IF EXISTS ',P_DB,'.TRG_',P_TAB,'_INSERT;\n');

    ## Insert Data
    SET @qry = CONCAT(@qry, 'INSERT IGNORE INTO ',P_DB,'.',P_TAB,' SELECT * FROM ',P_DB,'.',P_TAB,'_INSERT;\n');

    ## Delete Data
    SET @qry = CONCAT(@qry, 'DELETE A FROM ',P_DB,'.',P_TAB,' A INNER JOIN ',P_DB,'.',P_TAB,'_DELETE B ON A.',@ai_name,' = B.',@ai_name,';\n');

    ## Drop Temporary Tables
    SET @qry = CONCAT(@qry, 'DROP TABLE IF EXISTS ',P_DB,'.',P_TAB,'_INSERT;\n');
    SET @qry = CONCAT(@qry, 'DROP TABLE IF EXISTS ',P_DB,'.',P_TAB,'_DELETE;\n');
    SET @qry = CONCAT(@qry, '\n\n');
    SELECT @qry;
END$$
DELIMITER ;
```

# Conclusion

결과적으로 서비스 영향없이 무중단으로 테이블 스키마를 변경하였습니다. 만약 Update가 있는 경우라면 `INSERT INTO .. ON DUPLICATE KEY UPDATE..` 문을 사용하면 해결 가능하다는 생각이 드네요.^^ 물론 Update 트리거에도 Insert와 동일한 액션이 취해져야 하겠죠.

서비스 중단없이 DB 스키마를 변경했다는 점에서 큰 의의가 있었네요.^^