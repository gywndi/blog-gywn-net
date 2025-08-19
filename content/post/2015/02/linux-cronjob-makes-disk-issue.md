---
title: 새벽 4시, 이유없이 디스크 유틸이 튄다면? 디스크 성능에 영향을 주는 크론잡
author: gywndi
type: post
date: 2015-02-05T12:44:51+00:00
url: 2015/02/linux-cronjob-makes-disk-issue
categories:
  - MariaDB
  - MySQL
tags:
  - Linux
  - MySQL

---
# Overview

새벽에 디스크 성능에 영향을 주는 요소로는 대표적으로 백업과 같은 디비 운영적인 업무가 있습니다. 각 운영 정책에 따라 다르겠지만, 순간적인 시스템 부하에도 굉장히 민감한 서비스 경우에는 별도의 스탠바이 용도의 슬레이브 서버를 두고 그곳에서 백업을 하기 마련입니다.

이런 상황  마스터에서는 백업과 같은 무거운 디스크 작업이 일어나지 않는 상황에서 알 수 없는 이유로 새벽 4시 혹은 4시 22분에 디스크가 유틸이 튀는 경우가 있습니다. 그리고 가벼운 쿼리일지라도 대거 슬로우 쿼리로 잡히기도 합니다.

범인은 의외로 리눅스 설치 시 기본적으로 등록되는 두 가지 크론잡에 있는데요, 얼마 전 이와 비슷한 사례를 경험하게 되어 공유 드립니다. (단, 고수님들은 출입금지!)

# Default Cron Jobs

OS 설정에 따라 다르겠지만, CentOS를 설치하게 되면 다음과 같이 배치 작업이 등록이 되어 있습니다.

```bash
$ cat /etc/crontab
01 * * * * root run-parts /etc/cron.hourly >/dev/null 2>&1
02 4 * * * root run-parts /etc/cron.daily >/dev/null 2>&1
22 4 * * 0 root run-parts /etc/cron.weekly >/dev/null 2>&1
42 4 1 * * root run-parts /etc/cron.monthly >/dev/null 2>&1
```

이 상태에서 별다른 변경을 하지 않았다면 다음 두 개의 크론잡이 기본적으로 동작하게 되는데, 경우에 따라 두 개의 잡이 데이터베이스의 트랜잭션 로그 혹은 데이터 파일 쪽 디스크에 영향을 주어 순간 퍼포먼스가 크게 저하될 수 있습니다.

```bash
/etc/cron.daily/mlocate.cron
/etc/cron.daily/makewhatis.cron
/etc/cron.weekly/makewhatis.cron
```

간단하게 위 크론잡에 대해서 알아보도록 하겠습니다.

## 1) mlocate

파일 검색을 빠르게 검색하기 위해, 파일에 대한 색인 정보를 모아 데이터베이스를 만드는 역할을 하며, 매일 4시에 동작합니다.  
mloate.cron에 포함된 내용은 아래와 같습니다.

```bash
$ cat /ec/cron.daily/mlocate.cron

#!/bin/sh
nodevs=$(< /proc/filesystems awk '$1 == "nodev" { print $2 }')
renice +19 -p $$ >/dev/null 2>&1
/usr/bin/updatedb -f "$nodevs"
```

또한 이와 관련된 설정은 /etc/updatedb.conf 에 위치합니다.

```bash
$ cat /etc/updatedb.conf
PRUNEFS = "auto afs gfs gfs2 iso9660 sfs udf"
PRUNEPATHS = "/afs /media /net /sfs /tmp /udev /var/spool/cups /var/spool/squid /var/tmp"
```

  * PRUNEFS  
    updatedb 가 스캔하지 않을 파일 시스템 리스트
  * PRUNEPATHS  
    updatedb 가 스캔하지 않을 디렉토리 패스 리스트

매일 새벽 4시에 도는 작업으로 renice로 우선순위를 낮춰놓아도 디스크 자원을 아래와 같이 크게 잡아먹기도 합니다.

```bash
CPU     %user     %nice   %system   %iowait    %steal     %idle
all      0.00      0.51      3.03     46.46      0.00     50.00
all      0.00      1.01      4.55     44.44      0.00     50.00
all      1.00      0.50      2.00     47.50      0.00     49.00
all      0.51      0.00      2.03     47.72      0.00     49.75
all      0.50      0.50      3.50     46.50      0.00     49.00
```

만약 새벽 4시정도에 디스크 유틸이 이유없이 튀고 있다면, 이와 관련하여 살펴보시기 바랍니다.

## 2) makewhatis

처음 크론잡을 살펴보았을 때 별 것 아니라고 생각했었지만, 매주 일요일 새벽 4시 22분에 알 수 없는 디스크 유틸을 유발하던 장본인이었습니다.

간단하게 설명하자면, man에 관련된 내용을 신규 생성 또는 업데이트하며, 월~토요일은 증분으로 일요일은 전체를 풀로 새로 작성을 합니다.

```bash
## 일단위 크론잡
$ cat /etc/cron.daily/makewhatis.cron
.. 중략 ..
makewhatis -u -w

## 주단위 크론잡
$ cat /etc/cron.weekly/makewhatis.cron
.. 중략 ..
makewhatis -w
```

일 단위에서는 -u 옵션을 주어서, 기존 데이터베이스에 단순히 업데이트를 하지만, 주 단위 작업에서는 완전히 새로 작성합니다. 평일에는 크게 문제가 없다가 매주 일요일 새벽 4시 22분 정도에 시스템이 알 수 없이 튀는 현상을 보인다면, makewhatis 작업을 의심해보시기 바랍니다. ^^  
다음은 간단하게 테스트 장비에서 돌렸을 때의 시스템 상황입니다.(다를 수 있으니, 참고만 하세요. ^^)

```bash
CPU     %user     %nice   %system   %iowait    %steal     %idle
all     31.00      0.00     17.50      4.50      0.00     47.00
all     30.46      0.00     14.72      7.61      0.00     47.21
all     31.31      0.00     13.64      9.09      0.00     45.96
all     31.31      0.00     15.15      6.06      0.00     47.47
all     35.18      0.00     16.08      1.51      0.00     47.24
```

# Conclusion

운영 정책 및 트래픽에 따라 다르겠지만, 적어도 실DB 장비에서 굳이 디스크 자원을 소비하면서까지 이러한 인덱싱 혹은 매뉴얼을 작성할 필요는 없을 것이라 생각합니다. (물론 이것은 지극히 개인적인 소견이기는 하지만..^^)

만약 새벽 4시 이후로 알 수 없는 이유로 디스크 유틸이 튀고, 이로 인하여 슬로우 로그가 대거 발생하고 있다면 리눅스 새벽 크론작업을 의심해보시기 바랍니다.

(무언가 거창하게 시작했는데.. 성급하게 끝내버린 듯한 이 기분은 무엇일까요? ^^;;)