---
title: Linux Hot Copy(hcp) – Snapshot Tool
author: gywndi
type: post
date: 2013-12-10T03:53:02+00:00
url: 2013/12/let-me-know-linux-hot-backup
categories:
  - Research
tags:
  - backup
  - hcp
  - snapshot

---
# Overview

몇 달전 Linux Hot Copy(HCP) 유틸리티가 무료로 풀리면서, 고가의 스냅샷 유틸리티를 구입 없이도 얼마든지 사용할 수 있게 되었습니다. 스냅샷을 멋지게 활용할 수 있다면, 단순히 데이터 백업 뿐만 아니라 DB 시스템과 같이 복잡하게 얽혀서 구동되는 데이터도 특정 시점으로 데이터를 복사할 수 있습니다.

이 경우 Linux Hot Copy(hcp)에 대해 알아보도록 하겠습니다.

# Feature

  1. Point-in-Time 디스크 볼륨 스냅샷
  2. Copy on Write 방식의 Snapshot
  3. 서비스 영향없이 스냅샷을 생성

#### <Snapshot 비교>

  1. **Copy-on-Write**  
    Write 시 원본 데이터 Block을 Snapshot 스토리지로 복제하는 방식으로 Snapshot 데이터 Read 시 변경되지 않은 데이터는 원본 블록에서,변경된 데이터는 Snapshot 블록에서 처리  
    데이터 변경 분만 저장하므로 공간을 효율적으로 활용하나 블록 변경 시 원본 데이터와 스냅샷 데이터 양쪽 모두에서 Write이 발생
  2. **Redirect-on-Write**  
    Copy-on-Write와 유사하나, 원본 볼륨에 대한 Write을 별도의 공간에 저장하는 방식으로 Copy-on Write(원본 Read, 원본 Write, 스냅샷 Write)에 비해 Write이 1회만 발생하나, 스냅샷 해제 시 변경된 블록들을 원본 데이터 블록으로 Merge시켜야함
  3. **Split mirror**  
    원본 볼륨과 동일한 사이즈의 별도 복제 볼륨 생성하는 방식으로 데이터를 Full Copy하므로 즉시 생성이 어렵고 용량 또한 많이 필요

# Installation

설치 버전을 다운로드 하기 위해서는 하단 페이지에서 등록해야하는데, 등록하게 되면 설치 바이너리를 다운로드 받을 수 있는 별도의 링크를 메일로 보내줍니다. 완벽한 오픈소스는 아닌지라.. 설치하기가 조금은 짜증이 나지만.. 일단은..뭐.. ㅎㅎ

http://www.idera.com/productssolutions/freetools/sblinuxhotcopy
![hcp installation](/img/2013/12/hcp-installation.png)

설치 파일 압축을 풀면 아래와 같이 OS 별로 설치 바이너리가 있습니다.

```bash
$ unzip Idera-hotcopy.zip
$ cd Idera-hotcopy
$ ls
Idera-hotcopy.zip Installing+Hot+Copy.html idera-hotcopy-5.2.2.i386.rpm idera-hotcopy-5.2.2.x86_64.rpm idera-hotcopy-amd64-5.2.2.deb idera-hotcopy-i386-5.2.2.deb idera-hotcopy-i386-5.2.2.tar.gz idera-hotcopy-x86_64-5.2.2.tar.gz
```

서버에 사용하고자 하는 설치 바이너리를 설치합니다.

```bash
$ rpm -i idera-hotcopy-5.2.2.x86_64.rpm
$ hcp-setup --get-module
```

이제는 리눅스 커널에 맞는 모듈을 업그레이드해야 합니다. hcp-setup 명령어로 쉽게 가능하며, 업그레이드 시 https접근(443포트)이 필요합니다.

# Usage

사용법은 다음과 같이 hcp help 명령어를 통해 확인해볼 수 있습니다.

```bash
$ hcp --help
Usage: hcp -h | -m <MOUNT POINT> <DEVICE> | -l | -r <DEVICE>
Options:
  -h, --help             Show this help message.
  -l, --list             List active Hot Copy sessions.
  -r, --remove           Remove Hot Copy session.
  -m, --mount-point      Specify mount point.
  -o, --read-only        Mount hcp fs read only.
  -c, --changed-blocks   Specify changed blocks storage device.
  -q, --quota            Sets quota for changed blocks storage.
  -s, --show-hcp-device  Show the Hot Copy device path for a given
                         device.
  -v, --version          Show the Hot Copy driver version.
Examples:
    Start session:
        hcp /dev/sdb1
        hcp -m /mnt/tmp /dev/sdb1
    Remove session:
        hcp /dev/hcp1
    List sessions:
        hcp -l
```

변경된 블록들이 저장한 디바이스가 별도로 존재한다면 -c 옵션으로 스토리지를 분리할 수 있습니다. 그렇지 않으면, 스냅샷을 생성한 디스크에 기본적으로 변경 블록이 기록됩니다.

# **Example**

### **1) 스냅샷 생성  변경 블록이 저장될 스토리지(/dev/sdb1) 분리**

```bash
$ hcp -c /dev/sdb1 /dev/sdc1
Idera Hot Copy     5.2.2 build 19218 (http://www.r1soft.com)
Documentation      http://wiki.r1soft.com
Forums             http://forum.r1soft.com
Thank you for using Hot Copy!
Idera makes the only Continuous Data Protection software for Linux.
Starting Hot Copy: /dev/sdc1.
Changed blocks stored: /backup/.r1soft_hcp_sdc1
Snapshot completed: 0.000 seconds
File system frozen: 0.019 seconds
Hot Copy created: Tue Jul 18:31:02 KST 2013
Creating hotcopy snaphost device: /dev/hcp1, Please wait...
Hot Copy created at: /dev/hcp1
making new path: /var/idera_hotcopy/sdc1_hcp1
Mounting /dev/hcp1 read-write
Hot Copy mounted at: /var/idera_hotcopy/sdc1_hcp1
```

2) 스냅샷 현황

```bash
$ hcp -l
Idera Hot Copy     5.2.2 build 19218 (http://www.r1soft.com)
Documentation      http://wiki.r1soft.com
Forums             http://forum.r1soft.com
Thank you for using Hot Copy!
Idera makes the only Continuous Data Protection software for Linux.
****** hcp1 ******
 Real Device:           /dev/sdc1
 Virtual Device:        /dev/hcp1
 Changed Blocks Stored: /backup/.r1soft_hcp_sdc1.cow_hcp1
 Mounted:               /var/idera_hotcopy/sdc1_hcp1
 Time Created:          Tue Jul 18:31:02 KST 2013
 Changed Blocks:        0.25 MiB (262144 bytes)
```

**3) 스냅샷 삭제**

스냅샷이 마운트된 포인트를 인수로 줘서 스냅샷을 삭제합니다.

```bash
$ hcp -r /dev/hcp1
Idera Hot Copy     5.2.2 build 19218 (http://www.r1soft.com)
Documentation      http://wiki.r1soft.com
Forums             http://forum.r1soft.com
Thank you for using Hot Copy!
Idera makes the only Continuous Data Protection software for Linux.
Hot Copy Session has successfully been stopped.
All active Hot Copy sessions have been stopped. It is now safe to restart the Idera Backup Agent.
```

# Conclusion

Linux Hot Copy(hcp)는 설치 및 사용이 편리할 뿐만 아니라 무료로 사용할 수 있기에, 조금만 활용하면 멋진 백업 솔루션도 만들어낼 수 있습니다. 다음 번 포스팅에서는 이에 대한 내용을 정리해보도록 하겠습니다. ^^

HCP 스냅샷 유틸리티를 활용하여 DB의 시점 백업에 활용할 수 있는데, 다음번 이야기에서는 이 내용을 포스팅하도록 하겠습니다.