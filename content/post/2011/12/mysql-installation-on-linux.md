---
title: 리눅스에 MySQL 설치하기(CentOS 5.6)
author: gywndi
type: post
date: 2011-12-20T09:26:13+00:00
url: 2011/12/mysql-installation-on-linux
categories:
  - IT Life
  - MySQL
tags:
  - Linux
  - MySQL

---

MySQL DBMS 를 설치할 때 제가 적용하는 내용을 공유합니다. root 계정으로 설치 준비를 하고, mysql 계정으로 DB를 구동합니다.

일단 하단 내용들은 root계정으로 수행을 합니다.

### OS 계정 추가

다음과 같이 dba 그룹을 추가하고 그 밑에 mysql 계정을 추가합니다.

```bash
groupadd -g 600 dba
useradd -g 600 -u 605 mysql
passwd mysql
```

### Linux 설정 변경

세션 Limit 를 설정합니다.

```bash
vi /etc/security/limits.conf
##하단 내용 추가
mysql            soft    nproc  8192
mysql            hard    nproc  16384
mysql            soft    nofile 8192
mysql            hard    nofile 65536
```

OS에서 limits.conf 파일을 읽어들이도록 설정합니다. 없으면 생성합니다.

```bash
vi /etc/pam.d/login
## 하단 내용 추가
session    required     pam_limits.so
```

`/etc/profile` 에 다음 내용을 추가하여 login 시 적용되도록 합니다.

```bash
vi /etc/profile
##
if [ $USER = "mysql" ]; then
  if [ $SHELL = "/bin/ksh" ]; then
    ulimit -p 16384
    ulimit -n 65536
  else
    ulimit -u 16384 -n 65536
  fi
fi
```

MySQL 데이터 저장 디렉토리를 생성합니다.

```bash
mkdir -p /data/mysql/mysql-data
mkdir -p /data/mysql/mysql-tmp
mkdir -p /data/mysql/mysql-iblog
mkdir -p /data/mysql/mysql-binlog
```

### MySQL 설치 파일 다운로드

하단 실행 시 x86_64 가 있으면 64비트이고, i686 이 있으면 32비트입니다.

```bash
## OS 버전 확인 ##
uname -a
Linux ..중략.. EDT 2010 x86_64 x86_64 x86_64 GNU/Linux
```

이제 MySQL Download 의 Linux Generic 탭에서 자신의 OS에 맞는 MySQL Server 받으세요. 현재 Release되는 주 버전은 MySQL 5.5.x이나, 여기서는 MySQL 5.1.57 64비트 버전으로 설명드리겠습니다.

굴욕적이지만, 한국보다는 일본 mirror서버에서 받는 것이 빠르다는..-\_-;;

```bash
cd /usr/local/
## 설치 파일 다운로드
wget http://dev.mysql.com/get/Downloads/MySQL-5.5/mysql-5.5.19-linux2.6-x86_64.tar.gz/from/http://ftp.iij.ad.jp/pub/db/mysql/
```

### MySQL 기본 설정

시스템에 따라 데이터 파일과 같은 일부 변수 값이 달라질 수 있으니, 자신의 시스템에 맞게 수정해서 사용하세요.

```bash
vi /etc/my.cnf
```

```bash
[client]
port = 3306
socket = /tmp/mysql.sock

[mysqld]
# generic configuration options
port = 3306
socket = /tmp/mysql.sock

back_log = 100
max_connections = 500
max_connect_errors = 10
table_open_cache = 2048
max_allowed_packet = 16M
join_buffer_size = 8M
read_buffer_size = 2M
read_rnd_buffer_size = 16M
sort_buffer_size = 8M
bulk_insert_buffer_size = 16M
thread_cache_size = 128
thread_concurrency = 16
query_cache_type = 0
default_storage_engine = innodb
thread_stack = 192K
lower_case_table_names = 1
max_heap_table_size = 128M
tmp_table_size = 128M
local_infile = 0
max_prepared_stmt_count = 256K
event_scheduler = ON
log_bin_trust_function_creators = 1
secure_auth = 1
skip_external_locking
skip_symbolic_links
#skip_name_resolve

## config server and data path
basedir = /usr/local/mysql
datadir = /data/mysql/mysql-data
tmpdir = /data/mysql/mysql-tmp
log_bin = /data/mysql/mysql-binlog/mysql-bin
relay_log = /data/mysql/mysql-binlog/mysql-relay
innodb_data_home_dir = /data/mysql/mysql-data
innodb_log_group_home_dir = /data/mysql/mysql-iblog

## config character set
##utf8
character_set_client_handshake = FALSE
character_set_server = utf8
collation_server = utf8_general_ci
init_connect = "SET collation_connection = utf8_general_ci"
init_connect = "SET NAMES utf8"

## bin log
binlog_format = row
binlog_cache_size = 4M

## Replication related settings
server_id = 1
expire_logs_days = 7
slave_net_timeout = 60
log_slave_updates
#read_only

## MyISAM Specific options
key_buffer_size = 32M
myisam_sort_buffer_size = 8M
myisam_max_sort_file_size = 16M
myisam_repair_threads = 1
myisam_recover = FORCE,BACKUP

# *** INNODB Specific options ***
innodb_additional_mem_pool_size = 16M
innodb_buffer_pool_size = 2G

innodb_data_file_path = ibdata1:1G:autoextend
innodb_file_per_table = 1
innodb_thread_concurrency = 16
innodb_flush_log_at_trx_commit = 2
innodb_log_buffer_size = 8M
innodb_log_file_size = 128M
innodb_log_files_in_group = 3
innodb_max_dirty_pages_pct = 90
innodb_flush_method = O_DIRECT
innodb_lock_wait_timeout = 120
innodb_support_xa = 0
innodb_file_io_threads = 8

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no_auto_rehash

[myisamchk]
key_buffer_size = 512M
sort_buffer_size = 512M
read_buffer = 8M
write_buffer = 8M

[mysqlhotcopy]
interactive_timeout

[mysqld_safe]
open_files_limit = 8192
```

### MySQL Server 설치

```bash
## 압축 해제
cd /usr/local
tar xzvf mysql-5.5.19-linux2.6-x86_64.tar.gz
## 관리를 위한 심볼릭 링크 생성
ln -s mysql-5.5.19-linux2.6-x86_64 mysql
## 설치 파일 권한 변경
chown -R mysql.dba /usr/local/mysql*
## 시작 스크립트 복사
cp mysql/support-files/mysql.server /etc/init.d/mysqld
## 관련 파일 권한 설정
chown mysql.dba /data/mysql/*
chown mysql.dba /etc/my.cnf
chown mysql.dba /usr/local/mysql*
```

<span style="text-decoration: underline;"><strong>여기서부터는 이제 mysql 계정으로 실행을 합니다.</strong></span>  
관리를 위해서 몇몇 alias를 설정하는 부분입니다.^^

```bash
su - mysql
cat >> ~/.bash_profile
## 하단 내용 입력
export MYSQL_HOME=/usr/local/mysql
export PATH=$PATH:$MYSQL_HOME/bin:.
export ADMIN_PWD="ROOT 패스워드"

alias ll="ls -al --color=auto"
alias mydba="mysql -uroot -p$ADMIN_PWD"
alias mymaster="mysql -uroot -p$ADMIN_PWD -e'show master status;'"
alias myslave="mysql -uroot -p$ADMIN_PWD -e'show slave status\G'"
alias mh="cd $MYSQL_HOME"
alias md="cd /data/mysql/mysql-data"
alias mt="cd /data/mysql/mysql-tmp"
alias mb="cd /data/mysql/mysql-binlog"
alias mi="cd /data/mysql/mysql-data"
alias dp="cd /data/mysql/mysql-data"

## 환경 변수 적용
. ~/.bash_profile
```

### MySQL Server 구동

```bash
cd /usr/local/mysql
## 기본 데이터베이스 설치
./scripts/mysql_install_db
## MySQL 데몬 Startup
/etc/init.d/mysqld start
```

### MySQL 보안 설정

처음 DB를 올리면 보안 면에서 취약한 부분이 있습니다.  
기본적인 보안 정책을 적용하도록 합니다.  
mysql root  계정 패스워드만 설정하고 나머지는 Enter만 쭉 치면 됩니다.

```bash
cd /usr/local/mysql
./bin/mysql_secure_installation
```

```plain
NOTE: RUNNING ALL PARTS OF THIS SCRIPT IS RECOMMENDED FOR ALL MySQL
SERVERS IN PRODUCTION USE! PLEASE READ EACH STEP CAREFULLY!

In order to log into MySQL to secure it, we'll need the current
password for the root user. If you've just installed MySQL, and
you haven't set the root password yet, the password will be blank,
so you should just press enter here.

Enter current password for root (enter for none):
OK, successfully used password, moving on...

Setting the root password ensures that nobody can log into the MySQL
root user without the proper authorisation.

Change the root password? [Y/n]
New password:
Re-enter new password:
Password updated successfully!
Reloading privilege tables..
... Success!

By default, a MySQL installation has an anonymous user, allowing anyone
to log into MySQL without having to have a user account created for
them. This is intended only for testing, and to make the installation
go a bit smoother. You should remove them before moving into a
production environment.

Remove anonymous users? [Y/n]
... Success!

Normally, root should only be allowed to connect from 'localhost'. This
ensures that someone cannot guess at the root password from the network.

Disallow root login remotely? [Y/n]
... Success!

By default, MySQL comes with a database named 'test' that anyone can
access. This is also intended only for testing, and should be removed
before moving into a production environment.

Remove test database and access to it? [Y/n]
- Dropping test database...
ERROR 1008 (HY000) at line 1: Can't drop database 'test'; database doesn't exist
... Failed! Not critical, keep moving...
- Removing privileges on test database...
... Success!

Reloading the privilege tables will ensure that all changes made so far
will take effect immediately.

Reload privilege tables now? [Y/n]
... Success!

Cleaning up...

All done! If you've completed all of the above steps, your MySQL
installation should now be secure.
```

이제 MySQL DB 설치가 다 끝났습니다. 참 쉽죠잉~!^^