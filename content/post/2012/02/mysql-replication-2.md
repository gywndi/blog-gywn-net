---
title: MySQL Replication 이해(2) – 구성
author: gywndi
type: post
date: 2012-02-10T06:16:35+00:00
url: 2012/02/mysql-replication-2
categories:
  - MySQL
tags:
  - MySQL
  - Replication
  - 복제
  - 이중화

---
# Overview

MySQL Replication 개념에 이어, 이번에는 실 구성에 관한 내용입니다.  
각 서버 구성 방법은 [리눅스에 MySQL 설치하기](/2011/12/mysql-installation-on-linux/) 편을 참고하시기 바랍니다.

**시작에 앞서서 Server_id는 다른 숫자로 설정하세요^^.**

Replication 구성은 다음 세 단계를 거쳐서 수행됩니다.

  1. **DB 유저 생성**
  2. **DB 데이터 동기화(셋 중 택 1)**  
     - DB Data File Copy  
     - MySQL Dump (All Lock)  
     - Export/Import (Single Transaction)
  3. **리플리케이션 시작**

# 1. DB 유저 생성

복제 데이터 전송을 위한 리플리케이션 권한의 DB 유저를 마스터에 생성합니다. 각 슬레이브 IO 쓰레드들은 추가된 DB 유저를 통해 데이터를 받습니다.

```bash
[mysql@master] $ mysql -uroot -p비밀번호
 mysql> GRANT REPLICATION SLAVE ON *.*
     -> TO repl IDENTIFIED BY 'repl';
```

# 2. DB 데이터 동기화

* **DB Data File Copy  
DB 서버 데몬을 내린 상태에서 데이터 파일 자체를 복사하는 방식입니다. 데이터 파일 복사 과정만 수행하면 되기 때문에 대용량 서버에서 슬레이브 추가 시 유용한 방식입니다.
```bash
## MySQL 데몬 중지
[mysql@master] $ /etc/init.d/mysqld stop
[mysql@slave] $ /etc/init.d/mysqld stop

## 슬레이브에 데이터 복사
[mysql@slave] $ scp -r mysql@master:/data/mysql/mysql-data/data/mysql

## 마스터 바이너리 로그 파일 확인
[mysql@<strong>master**</strong>]$ cd /data/mysql/mysql-binlog
[mysql@<strong>master**</strong>]$ ls -alh
합계 21M
drwxr-xr-x. 2 mysql DBA 4.0K 13:34 .
drwxrwx---. 7 mysql DBA 4.0K 16:34 ..
-rw-rw----. 1 mysql DBA 21M  13:34 mysql-bin.000006
-rw-rw----. 1 mysql DBA 126 13:34 mysql-bin.000007**
-rw-rw----. 1 mysql DBA 126  13:34 mysql-bin.index
```

DB가 재시작되면 기본적으로 새로운 바이너리 로그를 생성됩니다.  
* 로그 파일명 : mysql-bin.000007, 로그 포지션: 106
* **MySQL Dump (All Lock)**  
  - **DB 전체에 READ LOCK을 걸고 데이터를 Export하는 방식입니다.**트랜잭션이 지원 안되는 스토리지 엔진이 섞여 있고, 데이터량이 작은 경우 사용하면 되겠습니다. [MySQL Table Lock에 관한 이해](/2012/01/mysql-table-lock/)와 같이 뜻하지 않은 Dead Lock이 발생할 수 있습니다.  
  - **Lock을 걸고 데이터를 Export 후 슬레이브 장비에서 다시 Import하는 방식입니다.** 백업하는 도중에는 데이터 변경 작업은 수행 불가하며, MyISAM의 경우 백업 수행 시간 동안 Dead Lock이 발생할 수 있습니다.  
  - 데이터량과 트랜잭션이 작은 경우 사용할 수 있는 방식입니다.
![MySQL Full Backup](/img/2012/02/mysql_full_backup.png)
    
```bash
##################
## 마스터 세션1>
##################
## READ LOCK을 걸어서 데이터 변경을 방지합니다.
mysql> FLUSH TABLES WITH READ LOCK;
Query OK, 0 rows affected (0.00 sec)

mysql> show master status\G
***** 1. row *****
File: mysql-bin.000008
Position: 456730
1 row in set (0.00 sec)

##################
## 마스터 세션2>
##################
## 다른 세션에서 전체 데이터를 백업합니다.
[mysql@master]$ export -uroot -p비밀번호 --all-databases > /data/mysql/mysql-dump/dump.sql

##################
## 마스터 세션1>
##################
## 원래 세션에서 READ LOCK을 해제합니다.
mysql> UNLOCK TABLES;
Query OK, 0 rows affected (0.00 sec)

## 슬레이브에 데이터 이관
[mysql@slave] $ scp -r mysql@master:/data/mysql/mysql-dump/dump.sql /data/mysql/mysql-dump
[mysql@slave] $ mysql -uroot -p비밀번호 --force > /data/mysql/mysql-dump/dump.sql
```

* **MySQL Dump (Single Transaction)** 
서비스 중지가 불가하고, 테이블이 트랜잭션을 지원하는 경우에만 사용할 수 있는 방법으로,트랜잭션 고립 (Isolation)을 특성을 활용하는 방식입니다. 즉, Database 가 InnoDB로만 이루어진 경우 많이 쓰입니다.
```bash
## 시점 데이터 생성
[mysql@<strong>master ~</strong>]$ export -uroot -p비밀번호 --single-transaction --master-data=2 --all-databases > /data/mysql/mysql-dump/dump.sql

## 슬레이브에 데이터 이관
[mysql@slave] $ scp -r mysql@master:/data/mysql/mysql-dump/dump.sql /data/mysql/mysql-dump
[mysql@slave] $ head -n 22 full_backup.sql | tail -n 1
-- CHANGE MASTER TO MASTER_LOG_FILE='mysql_bin.000008', MASTER_LOG_POS=456730;
[mysql@slave] $ mysql -uroot -p비밀번호 --force > /data/mysql/mysql-dump/dump.sql
```

# 3. 리플리케이션 시작

데이터 통신 용도로는 별도 네트워크에 구성해야 NIC 간섭을 최소화할 수 있습니다. 그리고 앞서서 기록을 해놓은 마스터 Binlog 파일과 포지션을 세팅 후 슬레이브 서버를 구동하면 되겠습니다.

```bash
## 슬레이브에서 실행
mysql> CHANGE MASTER TO
    -> MASTER_HOST='master-pri',
    -> MASTER_USER='repl',
    -> MASTER_PASSWORD='repl',
    -> MASTER_PORT=3306,
    -> MASTER_LOG_FILE='mysql-bin.000008',
    -> MASTER_LOG_POS=456730,
    -> MASTER_CONNECT_RETRY=5;
## 슬레이브 시작
mysql> START SLAVE;

## Slave_IO_Running, Slave_SQL_Running 상태 확인
mysql> show slave status\G
***** 1. row *****
               Slave_IO_State: Waiting for master to..
                  Master_Host: gisselldb01-pri
                  Master_User: repl
                  Master_Port: 3306
                Connect_Retry: 5
              Master_Log_File: mysql-bin.000008
          Read_Master_Log_Pos: 456730
               Relay_Log_File: mysql-relay.000001
                Relay_Log_Pos: 251
        Relay_Master_Log_File: mysql-bin.000008
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
            ..중략..
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 456730
              Relay_Log_Space: 547
              Until_Condition: None
            ..중략..
        Seconds_Behind_Master: 0
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 0
                Last_IO_Error:
               Last_SQL_Errno: 0
               Last_SQL_Error:
1 row in set (0.00 sec)
```

다음 편에는 실제 활용할 수 있는 분야에 관해서 정리하도록 하겠습니다.  
긴 글 읽으시느라 수고하셨어요^^