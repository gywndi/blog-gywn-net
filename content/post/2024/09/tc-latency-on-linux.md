---
title: 리눅스에서 tc로 레이턴시 조정해보기
author: gywndi
type: post
date: 2024-09-18T12:26:29+00:00
url: /2024/09/tc-latency-on-linux
categories:
  - Linux
tags:
  - Linux
  - tc

---
# Overview

일년만에, 블로그에 새 글을 올려봅니다. 그동안, 많은 주제가 있었지만, (주관적인 판단이지만) 좋은 주제일지 예전같은 확신이 서지 않아서, 많은 시간 망설이며 잠시 블로그를 멈추었습니다.

그러나, 제가 알던 경험이. 나만의 아련한 기억이 되고 점차 소멸되기 전에. 잊기 전에. 블로그 하나를 올려봅니다. 멀티DC 환경을 고려하면서, 몇가지 테스트를 하던 중. **노드간 네트워크 레이턴시를 고민**을 했었는데. **TC(Traffic control)를 활용하였고 나름 의미있는 결과를 도출**했었는데.. 오늘은 tc에 대해서 이야기를 해보고자 합니다.

# Traffic control (TC)?

동일 네트워크 상에서, **DC간의 레이턴시를 고려하여 성능 변화를 테스트하고 싶은 경우**가 있습니다. 특히나, 과거와는 다르게 서비스가 여러개의 DC 또는 Zone에서 분산 구동될 수 있다는 상황을 고려해본다면. 이런 테스트는 필수 입니다. 참고로, 아주 오래 전, 서울/부산 레이턴시 14ms로 인하여 대형 서비스 장애를 경험해본 입장으로. 서비스 오픈 전 이런 검증은 필수라 생각합니다. 

그렇다면, Linux에서는 동일 네트워크 상에서 레이턴시를 어떻게 부여해볼 수 있을까요?

Linux에는 TC(Traffic Control)라는 좋은 유틸이 있습니다. 이 유틸은 iproute에 포함된 것으로, 아래와 같이 패키지를 설치하면 간단하게 사용해볼 수 있습니다.

```bash
$ yum -y install iproute
```

Redhat8 버전에서 tc로 netem 을 사용하기 위해서는 추가 커널 모듈 설치가 필요합니다. 모듈 설치에는 서버 재시작은 굳이 필요 없습니다. ^^

```bash
$ yum install -y iproute-tc  
$ yum install kernel-debug-modules-extra kernel-modules-extra
```
# TC로 서버간 레이턴시 부여

아래와 같이 현재 IP가 `192.168.56.101`로 서버가 구동 중입니다. 그리고, `192.168.56.102` / `192.168.56.103` 모두 레이턴시가 0.3ms 입니다.

```bash
$ ifconfig
.. skip ..
eth1: flags=4163&lt;UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.56.101  netmask 255.255.255.0  broadcast 192.168.56.255
.. skip ..

$ ping -c 1 192.168.56.102 | grep ttl
64 bytes from 192.168.56.102: icmp_seq=1 ttl=64 time=0.360 ms

$ ping -c 1 192.168.56.103 | grep ttl
64 bytes from 192.168.56.103: icmp_seq=1 ttl=64 time=0.320 ms
```

자, 이 상태에서, `192.168.56.103` 에만, 추가로 30ms레이턴시를 부여해봅니다. 102번 서버는 여전히 0.3ms 정도로 레이턴스 변화가 없는 반면, 103서버만 30ms가 레이턴시가 증가된 것을 확인해볼 수 있습니다.

```bash
$ tc qdisc add dev eth1 root handle 1: prio
$ tc qdisc add dev eth1 parent 1:1 handle 10: netem delay 30ms
$ tc filter add dev eth1 protocol ip parent 1:0 prio 1 u32 match ip dst 192.168.56.103 flowid 1:1

$ ping -c 1 192.168.56.102 | grep ttl
64 bytes from 192.168.56.102: icmp_seq=1 ttl=64 time=0.280 ms

$ ping -c 1 192.168.56.103 | grep ttl
64 bytes from 192.168.56.103: icmp_seq=1 ttl=64 time=30.4 ms
```

# TC commands

이것 외에 유용한 명령어 몇개를 모아봅니다. TC를 처음 접했을 때, 개인적으로는 상당히 유용했습니다. ^^;;

```bash
## qdisc 리스트
$ tc qdisc list
qdisc noqueue 0: dev lo root refcnt 2
qdisc prio 1: dev eth1 root refcnt 2 bands 3 priomap 1 2 2 2 1 2 0 0 1 1 1 1 1 1 1 1
qdisc netem 10: dev eth1 parent 1:1 limit 1000 delay 10ms

## filter 상태
$ tc filter show dev eth1
filter parent 1: protocol ip pref 1 u32 chain 0
filter parent 1: protocol ip pref 1 u32 chain 0 fh 800: ht divisor 1
filter parent 1: protocol ip pref 1 u32 chain 0 fh 800::800 order 2048 key ht 800 bkt 0 flowid 1:1 not_in_hw
  match ac104371/ffffffff at 16
filter parent 1: protocol ip pref 1 u32 chain 0 fh 800::801 order 2049 key ht 800 bkt 0 flowid 1:1 not_in_hw
  match ac104371/ffffffff at 16

$ ping -c 1 192.16.56.100
PING 192.16.56.100 (192.16.56.100) 56(84) bytes of data.
64 bytes from 192.16.56.100: icmp_seq=1 ttl=64 time=10.2 ms

## 정책 삭제
$ tc qdisc del dev eth1 root
```

# Conclusion

**멀티DC 기반 클러스터 구성 시 영향도를 사전에 검증**해볼 수 있습니다. 

위에서는 단순히 레이턴시 정도만 지정해보았지만, 사실 대역폭을 비롯하여 패킷드랍 환경 등 아주 많은 설정들이 있습니다. 저는 Kafka를 Stretch cluster (여러 DC에 분산 구성한 클러스터)로 구성을 하였을 때. 각 DC간 레이턴시를 부여하는 식으로 환경을 마련하였고. 이로 인해 상당히 많은 의미있는 결론을 도출해보기도 했습니다. ^^

데이터 복제 구성이라면. 비동기 복제 시간에 따른 영향도도 사전에 파악해볼 수 있겠고. 저장소 클러스터 환경 구성 외에도. 캐시 아키텍처 검토를 위한 노드간 레이턴시 환경도 구성해볼 수 있겠습니다.

생각을 해보면. 서비스 오픈 전. 나름 레이턴시로 인한 영향도를 사전에 상당 부분 tc로 검증해볼 수 있다고 봅니다.

무더운 가을 날. 슬며시 컴백해서 유용한 지식 팁 하나 공유하며 오늘 포스팅을 마칩니다.