---
title: MySQL DB 데이터 이관 자동화 구현하기
author: gywndi
type: post
date: 2012-04-27T07:15:33+00:00
url: 2012/04/mysql_auto_db_migraion
categories:
- MySQL
tags:
- Migration
- MySQL

---
# Overview

DB를 운영하다 보면, 한 개의 MySQL 인스턴스에 여러 개의 데이터베이스를 모아서 보관하는 경우가 있습니다. 그러면 가끔 DB명이 충돌나는 경우도 발생하죠. 오늘은 Dump/Rename/Import 등 모든 프로세스를 자동화할 수 있는 방안을 제시해 봅니다.

# 요구사항

무조건 자동으로 동작해야 하고, 기억력이 나쁜 제가 나중에 사용하기 쉽게 재사용성도 좋아야한다는 것입니다. 그리고 사용 방법을 잊어도 쉽게 상기할 수 있는 방안도 있어야겠죠.ㅋ (제가 정한 요구사항입니다. ㅋ)

1. 모든 프로세스는 자동화되어야 한다.
2. 스크립트 수정 없이 재사용이 가능해야 한다.
3. 사용 매뉴얼이 있어야 한다.

# 자동화 구현

프로세스 순서는 다음과 같고 2단계부터는 파이프( | )로 한번에 처리합니다.

1. 인자 수 체크
2. 로컬 데이터베이스 Drop & Create (Rename)
3. 원격 데이터 Dump
4. Dump 파일에서 DB명 Rename
5. 로컬 데이터 베이스로 Import

# SHELL 스크립트

작성한 SHELL 스크립트 원본이고, 이관 작업은 데이터베이스 레벨로 이루어집니다. 테이블 레벨로의 확장은 하단 스크립트를 약간만 변경하면 될 것 같네요. (따로 구현은 안했습니다. ㅎ)

참고로 예전 포스팅 [리눅스에 MySQL 설치하기(CentOS 5.6)](/2011/12/mysql-installation-on-linux/) 대로 서버를 설치를 했으면, .bash\_profile 에 mysql root 패스워드가 명시되어 있을 것입니다. 아래 스크립트는 .bash\_profile 이 필요합니다.

```bash
#!/bin/sh

if [ $# -ne 5 ]; then
echo "Usage: ${0} <REMOTE_HOST> <REMOTE_DB> <REMOTE_DB_ID> <REMOTE_DB_PW> <LOCAL_TARGET_DB>"
echo "<Example>"
echo "REMOTE_HOST : 192.168.100.10"
echo "REMOTE_DB : snsdb"
echo "REMOTE_DB_ID : sns"
echo "REMOTE_DB_PW : sns12#"
echo "LOCAL_TARGET_DB : kth_snsdb"
echo "==> ${0} targetdb01 snsdb sns sns12# kth_snsdb"
exit 1
fi

## Exec profile for mysql user
. ~/.bash_profile

## Declare Valiables
REMOTE_HOST=${1}
REMOTE_DB=${2}
REMOTE_DB_ID=${3}
REMOTE_DB_PW=${4}
LOCAL_TARGET_DB=${5}

echo ">> Start Migration $db database"

echo ">> Drop and Create Database at Local Host"
mysql -uroot -p${ADMIN_PWD} -e"DROP DATABASE IF EXISTS ${LOCAL_TARGET_DB};CREATE DATABASE ${LOCAL_TARGET_DB};"

echo ">> Dump, Rename DB name, Insert Data"
mysqldump -u${REMOTE_DB_ID} -p${REMOTE_DB_PW} --host=${REMOTE_HOST} --single-transaction --no-create-db --databases ${REMOTE_DB} | sed -r 's/^USE `(.*)`;$/USE `'${LOCAL_TARGET_DB}'`/g' | mysql -uroot -p${ADMIN_PWD} ${LOCAL_TARGET_DB}

echo ">> Finish Migration $db database"
```

실제 사용은 다음과 같습니다.

```bash
$ ./mig_service_data 192.168.10.111 dbname dbuser dbpass dbname_renamed
>> Start Migration database
>> Drop and Create Database at Local Host
>> Dump, Rename DB name, Insert Data
>> Finish Migration database
```

모를 때는 아래와 같이 Script만 실행하면 매뉴얼이 나와요~

```bash
$ ./mig_service_data
Usage: ./mig_service_data <REMOTE_HOST> <REMOTE_DB> <REMOTE_DB_ID> <REMOTE_DB_PW> <LOCAL_TARGET_DB>
<Example>
REMOTE_HOST : 192.168.100.10
REMOTE_DB : snsdb
REMOTE_DB_ID : sns
REMOTE_DB_PW : sns12#
LOCAL_TARGET_DB : kth_snsdb
==> ./mig_service_data targetdb01 snsdb sns sns12# kth_snsdb
```

# Conclusion

위 프로세스는 Dump파일을 직접 열고, 데이터베이스 명을 원하는 이름으로 변경하여 진행해도 상관없습니다. 그러나 작은 운영이라도 최대한 자동화하여 운영 이슈를 최소화 하는 것을 저는 지향합니다. 설혹, 구현한 스크립트가 단 한번만 사용될 지언정^^;;