---
title: PowerDNS와 MySQL로 DNS를 해보고 싶어요~
author: gywndi
type: post
date: 2017-01-17T13:54:29+00:00
url: 2017/01/install_powerdns_with_mysql_backend
categories:
  - MySQL
  - Research
tags:
  - dns
  - mariadb
  - MySQL
  - powerdns

---
# Overview

PowerDNS란 범용적(?)으로 사용되는 오픈소스 기반의 DNS서버이고, 다양한 백엔드를 지원하는 멋진(?) DNS 이기도 합니다. 얼마전, 이 관련되어 간단한 사례에 대해 세미나를 진행을 하였고, 이 구성에 대한 설명이 미흡하여 간단하게 정리해봅니다. ^^

# Install PowerDNS

CentOS 6.7 버전에서 구성을 하였고, 실제 설치 작업에는 아래와 같이 같단합니다.  
(참고 : https://doc.powerdns.com/md/authoritative/installation/#binary-packages)

```bash
$ yum install pdns
$ yum install pdns-backend-mysql
```

(단, 여기서 MySQL 은 이미 구성되어 있다는 가정하에 진행합니다.)

# Configuration

자~ 이제 DNS 데몬을 설치하였으니..(두줄에.. 끝? -\_-;; 헐~)

이제,설정을 해보도록 합시다~ 먼저.. MySQL의 계정 및 스키마를 생성을 해보고..

```bash
$ mysql -uroot -p << EOF
  create database pdns_production;
  grant all on pdns_production.* to pdns@127.0.0.1 identified by 'pdns';
EOF
```

DNS 서버에서 사용할 스키마를 아래와 같이 생성을 합니다. 귀찮으니.. 그냥 콘솔 쉘에서 할 수 있도록.. 아래와 같이.. ㅋㅋ

```sql
$ mysql -uroot -p pdns_production << EOF
create table domains (
 id int auto_increment,
 name varchar(255) not null,
 master varchar(128) default null,
 last_check int default null,
 type varchar(6) not null,
 notified_serial int default null,
 account varchar(40) default null,
 primary key (id)
) engine=innodb;

create unique index name_index on domains(name);

create table records (
 id int auto_increment,
 domain_id int default null,
 name varchar(255) default null,
 type varchar(10) default null,
 content text default null,
 ttl int default null,
 prio int default null,
 change_date int default null,
 disabled tinyint(1) default 0,
 ordername varchar(255) binary default null,
 auth tinyint(1) default 1,
 primary key (id)
) engine=innodb;

create index nametype_index on records(name,type);
create index domain_id on records(domain_id);
create index recordorder on records (domain_id, ordername);

create table supermasters (
 ip varchar(64) not null,
 nameserver varchar(255) not null,
 account varchar(40) not null,
 primary key (ip, nameserver)
) engine=innodb;

create table comments (
 id int auto_increment,
 domain_id int not null,
 name varchar(255) not null,
 type varchar(10) not null,
 modified_at int not null,
 account varchar(40) not null,
 comment text not null,
 primary key (id)
) engine=innodb;

create index comments_domain_id_idx on comments (domain_id);
create index comments_name_type_idx on comments (name, type);
create index comments_order_idx on comments (domain_id, modified_at);

create table domainmetadata (
 id int auto_increment,
 domain_id int not null,
 kind varchar(32),
 content text,
 primary key (id)
) engine=innodb;

create index domainmetadata_idx on domainmetadata (domain_id, kind);

create table cryptokeys (
 id int auto_increment,
 domain_id int not null,
 flags int not null,
 active bool,
 content text,
 primary key(id)
) engine=innodb;

create index domainidindex on cryptokeys(domain_id);

create table tsigkeys (
 id int auto_increment,
 name varchar(255),
 algorithm varchar(50),
 secret varchar(255),
 primary key (id)
) engine=innodb;
create unique index namealgoindex on tsigkeys(name, algorithm);
EOF
```

pdns 설정 파일을 열어서.. 기본적으로  파일 기반인 BIND로 설정되어 있는 부분을 주석처리하고 MySQL접속 정보를 넣어줍니다. 위에서 계정 생성을 127.0.0.1로 접근 호스트를 생성하였으니.. 패스워드는 간단하게 설정하였습니다. (다른곳에서는 접근이 불가할테니요. ^^)

```bash
$ vi /etc/pdns/pdns.conf
#setuid=pdns
#setgid=pdns
#launch=bind

launch=gmysql
gmysql-host=127.0.0.1
gmysql-user=pdns
gmysql-password=pdns
gmysql-dbname=pdns_production
```

관리 서버를 올리고 싶다면.. 아래와 같이 pdns.conf에서 웹서버 부분을 변경 설정하여 올립니다. (여기서는 쿼리로만 추가 변경 테스트를 할테니, 굳이 필수 요소는 아닙니다. ^^)

```bash
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081

```

```bash
$ /etc/init.d/pdns start
```

이 모든 과정은.. 하단 메뉴얼에 친절하게 잘 명시되어 있고.. 제 입맛에 맞게 편집을 하였습니다. ㅋㅋ

참고 : https://doc.powerdns.com/md/authoritative/howtos/#basic-setup-configuring-database-connectivity

# DNS Test with SQL

먼저 아래와 같이 없는 DNS질의를 해보면 전혀~ 도메인에 대한 정보가 보여지지 않습니다.

```bash
$ dig +short aaa.db.io @127.0.0.1
```

이제 테스트를 위해 아래 쿼리를 밀어넣어줍니다. (참고로, 테이블에는 데이터가 전~혀 없다는 가정으로 테스트합니다.) 여기서 중요한 것은 SOA 는 필수입니다. 도메인의 영역을 표시할 뿐만 아니라, 어떻게 관리되어야할 지를 알려주는 도메인 Zone 개념을 내포하기 때문이죠.

저에게 중요한 것은 TTL이 0인 A타입의 도메인이기에.. A레코드인 경우는 TTL을 0으로 지정하여 넣어줍니다.

```bash
INSERT INTO domains (name, type) values ('db.io', 'NATIVE');
INSERT INTO records (domain_id, name, content, type,ttl,prio) VALUES
(1,'db.io','admin.db.io','SOA',86400,NULL),
(1,'aaa.db.io','192.0.0.1','A',0,NULL),
(1,'bbb.db.io','192.0.0.2','A',0,NULL),
(1,'ccc.db.io','192.0.0.3','A',0,NULL);
```

자. 아까 질의했던 도메인을 다시 확인해볼까요? 조금전에 DB에 밀어넣은 IP를 알려줍니다.

```bash
$ dig +short aaa.db.io @127.0.0.1
192.0.0.1
```

조금 더 자세하게.. 하단과 같이 질의를 해보면, TTL(ANSWER SECTION) 또한 0으로 잘~ 세팅되어 있다는 것도 확인할 수 있지요.

```bash
$ dig aaa.db.io @127.0.0.1

; <<>> DiG 9.8.2rc1-RedHat-9.8.2-0.47.rc1.el6 <<>> aaa.db.io @127.0.0.1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 21973
;; flags: qr aa rd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
;; WARNING: recursion requested but not available

;; QUESTION SECTION:
;aaa.db.io. IN A

;; ANSWER SECTION:
aaa.db.io. 0 IN A 192.0.0.1

;; Query time: 6 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Tue Jan 17 22:09:03 2017
;; MSG SIZE rcvd: 43
```

이제 쿼리로 도메인의 아이피를 바꿔볼까요?

```bash
$ mysql -uroot -p pdns_production << EOF
 update records set content = '192.0.0.4' where name = 'aaa.db.io'
EOF
```

쿼리 실행 후 DNS 질의를 해보면.. 바로 변경된 아이피를 확인할 수 있습니다.

```bash
$ dig +short aaa.db.io @127.0.0.1
192.0.0.4
```

이 내용 또한 앞선 매뉴얼의 테스트 내용을 약간 제 입맛에 맞게 살을 붙여서 만들어보았습니다.^^

# Conclusion

여전히 대부분의 DNS는 BIND기반으로 동작하고 있고.. 안정성 또한 입증된 방식이기도 하죠.

그렇지만 MySQL 을 백엔드로 가지는 PowerDNS는 DB가 가지는 강점.. 예를 들면 데이터 처리 및 보안 등등 BIND에서 가져갈 수 없는 강점을 가지기도 하지요. 이를테면.. 존 추가 이후에 서버 재시작이 필요없다거나.. 파일이 아닌 DNS쿼리 하나하나의 ROW Level Locking.. 트랜잭션 등등~~

이 포스팅에서는 간단하게.. 테스트를 수행할 수 있는 정도의 PowerDNS with MySQL 구성 방법을 설명해 보았습니다. 좋은 사례가 있으면 앞으로도 쭉 나왔으면 합니다. ^^

감사합니다.