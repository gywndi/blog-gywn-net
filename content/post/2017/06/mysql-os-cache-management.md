---
title: '[MySQL] 바쁜 서비스 투입 전, 이런 캐시 전략 어때요?'
author: gywndi
type: post
date: 2017-06-15T21:39:12+00:00
url: 2017/06/mysql-os-cache-management
categories:
  - MySQL
tags:
  - dentry
  - dirty
  - memory
  - MySQL
  - page cache
  - swap
  - unmap

---
# Overview

데이터베이스를 운영한다는 것은 최적의 상태로 리소스를 **쥐어짜면서** 가장 효율적으로 데이터를 끄집어내야할텐데요. 지금은 SSD 디스크 도입으로 상당 부분 Disk I/O가 개선되었다지만, 여전히 메모리 효율은 굉장히 중요합니다. 특히나 **Page Cache와 같은 항목이 과다하게 메모리를 점유하게 되면.. 다른 프로세스 효율에도 영향을 미칠 뿐만 아니라, 때로는 메모리 부족 현상으로 인하여 스왑 메모리에도 영향**을 줄 수 있습니다.

서론은 짧게.. 이번에 DBMS 구조를 그려가면서, 실제 리소스 사용에 걸림돌이 되는 몇몇 요소에 대한 우리의 사례를 얘기해보도록 하겠습니다.

# Page Cache

OS에서는 파일을 읽고 쓸때 디스크 I/O를 최소화하기 위해서 내부적으로 Page Cache 관리합니다. 매번 디스크에서 파일을 읽고 쓰면 효율이 떨어지기 때문인데.. SQLite과 같은 파일 기반의 DB라이브러리나, 정적인 데이터 쪽 Disk I/O가 빈번하게 발생하는 곳에서는 극도의 효율을 보여주겠죠.

```bash
$ free
             total       used       free     shared    buffers     cached
Mem:       2043988    1705544     338444       7152     188920     330648 <==
-/+ buffers/cache:    1185976     858012
Swap:      4800508          0    4800508

```

문제는 **솔루션 자체적인 캐시 공간을 가지는 경우, 이를테면 MySQL InnoDB에서와 같이 InnoDB_Buffer_Pool 영역을 가지는 경우**에는 이러한 Page Cache 큰 의미가 없습니다. DB에서 1차적으로 가장 빈도있게 액세스 요청하는 곳은 자체 버퍼 캐시이기 때문이지요. 그래서 이러한 경우 **Page Cache 사용을 최소화하도록 유도하거나, 아예 캐시레이어를 태우지 않고 바로 데이터 파일로 접근(O_Direct)**하는 것이 좋습니다. 이러한 경우를 떠나, TokuDB와 같이 Page Cache에서 압축된 파일을 보관하는 것이 효율면에서 좋은 경우.. 다른 엉뚱한 곳에서 캐시 영역을 점유하지 않도록 유도하는 것도 필요합니다.

Percona에서 InnoDB의 Fork로 컴파일하여 배포하는 XtraDB 스토리지 엔진에는 이러한 요구사항에 맞게 데이터파일 및 트랜잭션 로그(Redo/Undo) 접근에 Page Cache를 끼지 않고, 직접 데이터 파일에 접근할 수 있도록 `innodb_flush_method`에 `ALL_O_DIRECT` 옵션을 제공해줍니다. (https://www.percona.com/doc/percona-server/5.6/scalability/innodb_io.html#innodb_flush_method)

문제는 `ALL_O_DIRECT`를 사용했을지라도, 여전히 **Binary Log 혹은 기타 로그(General Log, Error Log, Slow Log)에 대해서는 여전히 Page Cache를 사용한다**는 점입니다.만약 쓰기 작업이 굉장히 빈번한 서비스에서는 다수의 바이러리 로그가 발생할 것이고.. 이로인해 Page Cache 영역이 생각보다 과도하게 잡힐 소지가 분명 있습니다.

그래서 요시노리가 오픈한 unmap_mysql_logs 를 참고하여, 우리의 요구사항에 맞게 조금 변형하여 재구성해보았습니다. (https://github.com/yoshinorim/unmap_mysql_logs)

1. **서버에 기본 이외에 설치는 굉장히 어렵다. 우리는 금융이니까.**
2. **서버마다 컴파일하기는 싫고, 복/붙만으로 처리하고 싶다.**
3. **unmap 대상을 유연하게 변경하고 싶다.(추가 컴파일 없이)**

그래서 파라메터로 특정 파일을 전달받고, 해당 파일을 unmap 수행하도록 아래와 같이 main 프로그램을 추가하여 재작성하였고, 로그 대상은 별도의 쉘 스크립트로 제어하여 매번 컴파일 없이도 유연성있게 제어하도록 변경하였습니다.

```cpp
int main(int argc, char* argv[]){
  if(argc == 1){
    fputs("no options\n", stderr);
    exit(1);
  }

  int i = 0, r = 0;
  for (i = 1; i &lt; argc; i++){
    printf("unmap processing.. %s.. ", argv[i]);
    unmap_log_all(argv[i]) == 0 ? printf("ok\n") :  printf("fail\n");
  }
}
```

자세한 내용은 하단 github을 참고하세요. 🙂  
https://github.com/gywndi/kkb/tree/master/mysql_cache_unmap

# Dirty Page

Dirty Page는 얘기를 여러번 해도 부족함이 전혀 없습니다. 다른 것보다 가장 문제시 되는 것은 하단 붉은색 표기입니다. 매 5초(`vm.dirty_writeback_centisecs`)마다 `pdflush` 같은 데몬이 깨어나, 더티 플러시를 해야할 조건이 왔는지를 체크하게 되는데요. 문제는 기본값 10은 메모리의 10% 비율이라는 말이지요. 데이터 변경량이 적은 경우는 문제가 안되는데, **굉장히 바쁜 서버 경우에는 이로 인해 문제가 디스크 병목이 발생**할 수 있겠습니다.

**한번에 다량의 데이터를 디스크로 내리지 말고, 조금씩 자주 해서 디스크의 부담을 최소화**하자는 것인데요. RAID Controller에 Write-Back이 있을지라도 혹은 디스크 퍼포먼스가 엄청 좋은 SSD일지라도 수백메가 데이터를 한번에 내리는 것은 부담이기 때문이죠. 특히 크고 작은 I/O가 굉장히 빈번한 데이터가 살아 움직이는 DBMS 인 경우!!

스왑 메모리 또한 서비스 효율 측면에서 굉장히 이슈가 있는데요. 아무리 SSD 디스크의 강력한 Disk I/O가 받혀줄지라도, 실제 메모리의 속도를 절대적으로 따라갈 수 없습니다. 페이지 캐시든 다른 요소이든, 비효율적인 어떤 요인에 의해 DBMS에서 사용하는 메모리 영역(InnoDB경우 Innodb_buffer_pool 이죠)이 절대로 스왑 메모리로 빠져서는 안됩니다.

```bash
$ sysctl -a | grep dirty
vm.dirty_background_ratio = 10
vm.dirty_background_bytes = 0 <==
vm.dirty_ratio = 20
vm.dirty_bytes = 0
vm.dirty_writeback_centisecs = 500
vm.dirty_expire_centisecs = 3000

$ sysctl -a | grep swap
<strong><span style="color: #ff0000;">vm.swappiness = 60
</span></strong>
```

그래서 아래와 같이 더티 파라메터를 비율이 아닌 고정값으로 임계치가 설정되도록 `vm.dirty_background_bytes` 값을 변경해줍니다. 그리고,스왑 메모리 사용을 최대한 지양하고자.. `vm.swappiness` 파라메터를 1로 설정하도록 합니다.

```bash
$ sysctl vm.dirty_background_bytes=100000000
$ sysctl -w vm.swappiness=1
```

뭐.. 개인적으로는 스왑이 발생해서 서비스 품질이 떨어지는 것보다는, 스왑 없이 메모리 부족 현상으로 해당 프로세스가 OOM으로 강제 킬되어 명확하게장애로 노출이 되어서 페일오버 단계로 명쾌하게 넘어가는 것이 좋다고 생각합니다만..아무래도 금융 서비스인만큼.. 보수적으로 접근해서 스왑 파라메터를 1로 설정하였습니다.

아. 위처럼 커널 파라메터를 바꿔봤자, OS 재시작되면 원래 기본 값으로 돌아갑니다. 반드시 `/etc/sysctl.conf` 파일에 파라메터 값을 추가하세요.

# Dentry

금융권 DB를 구성하면서, 처음으로 겪은 현상이었습니다. 이상하게 메모리 사용률이 높은 것이지요.

위와같이 매 5분마다 Page Cache를 unmap함에도 불구하고, 전체적으로 메모리 사용량이 거의 95%를 훌쩍 넘게 사용하는 현상을 보였습니다. 처음에는 MySQL 버퍼 캐시 영역이 차지한다고 생각을 했었는데..slabtop으로 메모리 사용 현황을 살펴본 결과 dentry(하단 강진우 님 브런치 참고) 에서 대부분점유 중인 것을 확인할 수 있었습니다. (당시 상황 캡쳐를 못해서.. 그냥 재시작 후 3일된 서버로.. 대체합니다.)

```bash
$  slabtop
 Active / Total Objects (% used)    : 15738668 / 15746877 (99.9%)
 Active / Total Slabs (% used)      : 783666 / 783672 (100.0%)
 Active / Total Caches (% used)     : 116 / 204 (56.9%)
 Active / Total Size (% used)       : 2949065.50K / 2950582.13K (99.9%)
 Minimum / Average / Maximum Object : 0.02K / 0.19K / 4096.00K

  OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME
14565320 14565248  99%    0.19K 728266       20   2913064K dentry <==
926480 925875  99%    0.10K  25040       37    100160K buffer_head
 50848  50814  99%    0.98K  12712        4     50848K ext4_inode_cache
```

참고로, 우리는 금융 서비스이기 때문에.. 보안 강화(?)를 위해 타 서버와의 curl로 REST API 사용을 하기 위해서는 일단 기본적으로 https로 백업 결과 혹은 서버 상태 전송을 중앙 서버로 전송을 합니다. (거의 필수로)

그리고 카카오의 슈퍼 루키 강진우(alden)님의 조언을 얻어.. curl로 https로 이루어진 REST API를 호출하면서 발생하는 현상임을 확인했습니다. (https://brunch.co.kr/@alden/28)

참고로 하단은 내부적으로 이 관련 내용을 증명/분석(?)하기위해, 우리 팀 슈퍼 에이스 성세웅 님의 테스트결과를 훔쳐옵니다. 🙂

```bash
$ unset NSS_SDB_USE_CACHE
$ strace -fc -e trace=access curl --connect-timeout 5 --no-keepalive \
  "<a href="https://testurl/api/host.jsp?code=sync&host_name=&#96;hostname" target="_blank">https://testurl/api/host.jsp?code=sync&host_name=`hostname</a><span class="leading-spaces"></span>-s`" &gt; /dev/null
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00    0.000081           0      2731      2729 access
 <==
```

자! 이번엔 Mr.강의 조언에 따라 `export NSS_SDB_USE_CACHE=yes` 를 설정한 이후 결과를 살펴봅시다.

```bash
$ export NSS_SDB_USE_CACHE=yes
$ strace -fc -e trace=access curl --connect-timeout 5 --no-keepalive \
  "https://testurl/api/host.jsp?code=sync&host_name=`hostname -s`" &gt; /dev/null
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
  0.00    0.000000           0        10         7 access
 <==
```

2729 VS 7..NSS_SDB_USE_CACHE가 세팅되지 않은 상태에서 간단한 프로그램으로 루핑을 돌면서 curl API를 호출했을 때 선형적으로 dentry 영역이 증가하는 것을 확인할 수 있었습니다. `/etc/profile`에 `export NSS_SDB_USE_CACHE=yes` 추가하여 비정상적인 메모리 사용 현상은 사라지게 되었죠. ㅎㅎ

# Conclusion

그간의 경험들이 굉장히 무색해지는 산뜻한 경험입니다. **조금더 편하게, 조금더 유연하게, 조금더 안정적으로**를 지난 몇 달 간 고민을 했었고, 운영 시 **최소한의 사람 리소스로 최대의 효율을 획득**할 수 있도록 발버둥쳤고, 그 과정에서 많은 것을 배웠습니다.

  1. **Page Cache를 주기적으로 unmap하여 메모리 효율 증대**
  2. **Dirty/Swap관련 파라메터 조정**
  3. **dentry 캐시 사용에 따른NSS_SDB_USE_CACHE 파라메터 설정**

오픈된 지식으로 많은 것을 얻었고, 저 역시 얻은 것을 다른 누군가에게 오픈을 해서, 누군가의 새로운 오픈된 지식을 얻고자 이렇게 블로그에 정리를 해봅니다. (사실은 여기저기 흩어진 정보들이 너무 산발되어 정리할 필요성을 느꼈기에.. ㅋㄷㅋㄷ, 그래도 힘드네요. ㅠㅠ)

좋은 밤 되세요. ^^