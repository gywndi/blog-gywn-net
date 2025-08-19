---
title: 디스크 병목 현상에 따른 DB 성능 리포트
author: gywndi
type: post
date: 2012-03-18T10:05:35+00:00
url: 2012/03/database-performance-report-on-disk-bottleneck
categories:
  - MySQL
  - Research
tags:
  - Benchmark
  - Bottleneck
  - MySQL

---
# Overview

어느 시스템에서도 병목 현상은 어딘가에 있습니다. DBMS 또한 CPU, Memory, Disk로 구성된 하나의 시스템이기 때문에 당연히 특정 구역에서 병목현상이 발생할 수 있죠. 오늘은 Disk에서 발생하는 병목에 관해서 말씀드리겠습니다.

# Memory Processing

[Permanent Link: 디스크 배열(RAID)에 따른 DB 성능 비교](/2012/03/db-performance-disk-raid-configuration/) 에서, 메모리가 충분하면 아래와 같다는 그래프를 보여드렸습니다.

![InnoDB Buffer Pool : 12G](/img/2012/03/buffer_pool_12G_disk1.png)

어떤 경우든 메모리에만 연산이 가능하다면, CPU자원을 거의 활용 가능하다고 할 수 있죠. 그러나 만약 디스크 I/O가 발생하는 순간부터 CPU는 전혀 연산하지 않는 현상이 발생합니다. 바로 디스크 I/O Wait 으로 인한 시스템 병목 현상 발생입니다.

# Benchmark

대용량 환경에서 MySQL 성능을 분석하기 위해 2억 데이터 Insert 테스트를 수행하였습니다. (하단 결과에서는 1.3억 데이터까지만 추출하여 그래프를 만들었습니다.)

하단은 테스트를 위해 사용한 테이블 스키마입니다. (간단한 테스트입니다.) 30개 Thread로 동시 Insert 작업을 수행하였고, 건 수에 따라 QPS및 시스템 현황을 살펴보았습니다.

```sql
##테이블 정의
CREATE TABLE `test` (
`NO` int(11) NOT NULL AUTO_INCREMENT,
`EMAIL` varchar(128) DEFAULT NULL,
`NAME` varchar(32) NOT NULL,
PRIMARY KEY (`NO`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
PARTITION BY KEY ()PARTITIONS 3;

##테이블 포멧 변경
TRUNCATE TABLE TEST;
ALTER TABLE TEST ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=4;
```

# Benchmark Result

버퍼풀 4G 환경 하의 일반 테이블과 압축 테이블 성능 비교 및 버퍼풀 8G 환경 하에서의 성능 비교입니다.  
압축 테이블의 경우 생각보다 많은 CPU 작업이 필요하게 되는데요, 메모리에 모든 데이터가 존재한다면 이 자체가 병목입니다.  
하지만 데이터가 급증하여 DISK I/O이슈가 발생하면 반대로 CPU 유휴 자원을 사용하여 병목을 줄일 수 있습니다.

![디스크 압축에 따른 QPS 비교](/img/2012/03/QPS_none-compressed_vs_compressed_table.png)

![디스크 압축에 따른 DISK I/O 비교](/img/2012/03/DISK_none-compressed_vs_compressed_table.png)

7000만 건 데이터(데이터파일 약 5G) Insert까지는 일반 테이블이 압도적인 성능을 보여줍니다. 7000만 건 이상 데이터 Insert에서는 1/4로 압축한 테이블 성능이 꾸준히 유지됩니다. 9000만 건 데이터 Insert부터 1/4 압축 테이블도 성능 저하가 발생합니다.

**가장 괄목할만한 사항은 DISK I/O가 급증하는 시점부터는 CPU자원은 거의 사용하지 않는다는 점입니다.**

# Conclusion

디스크 병목을 풀기 위해서 더욱 빠른 디스크로 고도화하여 풀 수 있는 방법이 있습니다. 다른 방법은 어차피 사용하지 못할 CPU자원이라면, CPU자원을 일부 소모하더라도 압축 테이블로 저장하여 디스크 병목을 해결할 수 있습니다.

앞선 테스트 결과가 반드시 정답은 아닙니다. 무조건 압축 테이블만이 대안은 아닙니다. 하지만 서비스 특성에 맞게 테스트 시나리오를 작성하고 병목을 사전에 최대한 줄이는 활동이 필요합니다.

무조건 고 사양의 서버로 구성하기 보다는 조금만 데이터를 다른 시각으로 설계한다면, 동일 자원에서 최적의 퍼포먼스를 발휘할 수 있을 것입니다.
