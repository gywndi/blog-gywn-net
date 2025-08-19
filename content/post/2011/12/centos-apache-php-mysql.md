---
title: CentOS6 에 Apache+PHP+MySQL 구성
author: gywndi
type: post
date: 2011-12-11T12:44:24+00:00
url: 2011/12/centos-apache-php-mysql
categories:
  - IT Life
tags:
  - Apache
  - CentOS
  - Linux
  - MySQL
  - PHP
  - 설치

---
서버를 구성하면서 사용한 스크립트..  
나중에 재사용을 위해서 블로그에 올리자!!  
Apache -> MySQL -> PHP 순으로 설치!

모든 설치 파일 혹은 소스는 하단 디렉토리에 위치한다.

* **Apache:** http://apache.org
* **MySQL :** http://dev.mysql.com
* **PHP   :**  http://php.net

최근 릴리즈 버전을 `/usr/local/src`에 다운로드 한다.

## Apache 설치

```bash
## 컴파일 및 설치
cd /usr/local/src
tar xvzf httpd-2.2.14.tar.gz
cd httpd-2.2.21
./configure --prefix=/usr/local/apache \
--enable-mods-shared=all \
--enable-so \
--enable-module=rewrite
make
make install

## 관리를 위해 Symbolic Link로 연결
cd /usr/local
mv apache apache-2.2.21
ln -s apache-2.2.21 apache
```

### MySQL 설치

```bash
## 압축 해제 설치
tar xzvf mysql-5.5.19-linux2.6-x86_64.tar.gz
mv mysql-5.5.19-linux2.6-x86_64 /usr/local/
cd /usr/local

## 관리를 위해 Symbolic Link로 연결
ln -s mysql-5.5.19-linux2.6-x86_64 mysql
```

자세한 설치는 [리눅스에 MySQL 설치하기(CentOS 5.6)](/2011/12/mysql-installation-on-linux/) 편을 참고하세요.

### PHP설치

```bash
## 필요 라이브러리 설치
## 추가 필요한 라이브러리는 yum 으로 따로 업데이트
yum install libzip* libcurl* openssl*

## 컴파일 및 설치
tar xzvf php-5.3.8.tar.gz
cd php-5.3.8
./configure --prefix=/usr/local/php \
--with-apxs2=/usr/local/apache/bin/apxs \
--with-mysql=/usr/local/mysql \
--with-config-file-path=/usr/local/apache/conf \
--with-exec-dir=/usr/local/apache/bin \
--enable-sigchild \
--with-curl \
--with-openssl \
--with-curlwrappers \
--with-gd \
--enable-ftp \
--enable-zip \
--disable-debug

make
make install
cp php.ini-production /usr/local/apache/conf/php.ini

## 관리를 위해 Symbolic Link로 연결
cd /usr/local
mv php php-5.3.8
ln -s php-5.3.8 php
```

### Apache 환경 변수 변경

```bash
vi /usr/local/apache/bin/envvars
## 하단 내용 추가
export MYSQL_HOME=/usr/local/mysql
export PATH=$PATH:$MYSQL_HOME/bin:.
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MYSQL_HOME/lib/
```

### httpd.conf 변경

```bash
vi /usr/local/apache/conf/httpd.conf

## 인덱스 파일에 php 추가

DirectoryIndex index.php index.html index.htm

## 주석 제거
Include conf/extra/httpd-vhosts.conf
Include conf/extra/httpd-default.conf

## 하단에 Type 추가
AddType application/x-httpd-php .php
AddType application/x-httpd-php-source .phps
```

### 가상 호스트 설정

```bash
vi /usr/local/apache/conf/extra/httpd-vhosts.conf

## 디렉토리 설정 및 가상 호스트 추가

Options Indexes FollowSymLinks
AllowOverride All
Order allow,deny
Allow from all



ServerName gywn.net
ServerAdmin gywndi@gmail.com
DocumentRoot "/data/www/gywn.net"
ServerAlias www.gywn.net
ErrorLog "logs/gywn.net-error_log"
CustomLog "logs/gywn.net-access_log" common

```

### 서비스 등록

```bash
## 아파치 #################
cp /usr/local/apache/bin/apachectl \
/etc/init.d/httpd
vi /etc/init.d/httpd
## "#!/bin/sh" 밑에 하단 라인 추가
# chkconfig: 2345 90 90

## MySQL #################
cp /usr/local/mysql/support-files/mysql.server \
/etc/init.d/mysqld

## 서비스 등록
chkconfig --add httpd
chkconfig --add mysqld
```

다음 서버 세팅은 이로서 조금은 편해질듯^^  
삽질은 삽질일 뿐 두번하지 말자!