---
title: 디스크 배열(RAID)에 따른 DB 성능 비교
author: gywndi
type: post
date: 2012-03-18T09:43:46+00:00
url: 2012/03/db-performance-disk-raid-configuration
categories:
  - MySQL
  - Research
tags:
  - Benchmark
  - MySQL
  - RAID

---
# Overview

MySQL DBMS 하드웨어 구성 시 어떠한 정책으로 움직이는 것이 가장 효율적일지, 메모리/디스크 설정을 변경하여 테스트를 진행하였습니다. 디스크는 RAID 레벨을 변경하였고, innodb\_buffer\_pool을 조정함으로써 메모리 환경을 구성하였습니다. 서비스 특성에 따라 하드웨어 구성을 달리함으로써, 장비를 더욱더 효율적으로 사용할 수 있을 것으로 기대됩니다.^^

# 디스크배열(RAID)란?

RAID란 Redundant Array of Inexpensive Disks의 약자로 디스크를 여러장 묶어서, 데이터 중복성 및 성능 향상을 유도할 수 있는 기법입니다. RAID 기법은 참으로 많이 있으나, 일반적으로 실무에서는 RAID0, RAID1, RAID5, RAID10또는 RAID01을 많이 사용합니다.

# Benchmark 

테스트 환경은 다음과 같습니다.
- CPU: Intel(R) Xeon(R) CPU E5630  @ 2.53GHz Quad * 2EA
- Memory(InnoDB Buffer Pool):
  - 12G : 데이터 100%가 메모리 안에 존재 (DISK I/O 없음)
  - 8G : 데이터 80% 가 메모리 안에 존재 (DISK I/O 일부 발생)
  - 4G : 데이터 40% 미만 메모리 안에 존재 (DISK I/O 다량 발생)
- DISK RAID
  - RAID1 : 데이터/로그 디스크 공유
  - RAID1(2) : 데이터/로그 디스크 분리
  - RAID5 : 데이터/로그 디스크 공유
  - RAID10 : 데이터/로그 디스크 공유
- 데이터 사이즈: 50,000,000건 (11G)
- 동시 접속 수: 1, 5, 10, 15, 20, 30, 100
- 트랜잭션 구성
  - READ-ONLY : 14 Queries (–oltp-read-only –oltp-skip-trx)
  - READ/WRITE : 19 Queries (–oltp-test-mode=complex)

# Benchmark Result

  * **Innodb\_Buffer\_Pool Size : 12G**  
    테스트 결과 모두 비슷한 성능을 보여주나 100쓰레드에서는 raid1(2) 시 일부 성능이 저하되었습니다. (iblog에서 데이터 저장 공간에 적용 시 물리적 장치 분리에 의한 성능 저하 요인으로 파악되네요.) 
    ![InnoDB Buffer Pool : 12G](/img/2012/03/buffer_pool_12G_disk1.png)
    
  * **Innodb\_Buffer\_Pool Size : 8G**  
    READ/WRITE에서는 디스크 배열에 따라 상당한 성능 차이를 보이는데, Buffer-Pool안의 데이터가 디스크로 Flush 되면서 발생하는 데서 기인한 듯 하고, RAID10이 가장 안정적인 성능을 보여줍니다. 
    ![InnoDB Buffer Pool : 8G](/img/2012/03/buffer_pool_8G_disk.png)
        
  * **Innodb\_Buffer\_Pool Size : 4G**  
    가장 재미있는 결과입니다. 디스크 의존도가 높기 때문에 당연히 Raid-10이 가장 우수합니다. 그 다음으로는 Raid-5, Raid-1 순으로 성능을 보입니다. 
    ![InnoDB Buffer Pool : 4G](/img/2012/03/buffer_pool_4G_disk_1.png)
            
# **Conclusion**

위 결과를 바탕으로 다음과 같이 결론짓고 싶습니다.

* 예산이 허용한다면, 다수의 디스크를 사용한 Raid-10으로 구성
* 빈번하게 사용되는 데이터가 메모리에 80% 이상 존재한다면 Raid-1도 괜찮은 성능을 보임 (특히 Read 시)
* 데이터 변경 작업이 많은 DB인 경우 반드시 Raid5또는 Raid10으로 구성
* 성능 확장에는 메모리 투자가 제일 유리

메모리에 데이터가 모두 존재할 수 있다면, CPU성능에 따라 TPS 결과가 나옵니다. 4000이상 TPS가 나오는 경우 CPU idle이 거의 0% 까지 떨어지기 때문에, 여기서부터는 CPU투자에 따라 결과가 좌우되겠죠.

감사합니다.