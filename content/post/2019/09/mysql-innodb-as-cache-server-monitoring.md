---
title: MySQL InnoDB의 메모리 캐시 서버로 변신! – 모니터링편 –
author: gywndi
type: post
date: 2019-09-19T14:28:50+00:00
url: 2019/09/mysql-innodb-as-cache-server-monitoring
categories:
  - MariaDB
  - MySQL
  - PMM
tags:
  - exporter
  - memcached
  - MySQL
  - prometheus

---
# Overview

MySQL memcached plugin 2탄! 모니터링편입니다.  
어떤 초호화 솔루션일지라도, 시스템의 정확한 상태를 파악할 수 없다면, 사용하기에는 참으로 꺼려집니다. 그래서 어떤 방법이든, **가장 효율적인 모니터링 방안**을 찾아봐야 하겠는데요. 저는 개인적으로는 **prometheus를 활용한 metric수집을 선호**합니다.  
오늘 이 자리에서는 Prometheus에서 MySQL InnoDB memcached plugin을 모니터링 하는 방법에 대해서 이야기를 해보도록 하겠습니다. 🙂

# Why prometheus?

이유는 단순합니다. **이미 만들어져 있는 exporter가 굉장히 많다**는 것, 만약 원하는 것들이 있다면 **나의 구미에 맞게 기능을 추가해서 쉽게 접근할 수 있다**는 것! 즉, **오픈소스**라는 것!! 무엇보다 Time-series 기반의 데이터 저장소인 Prometheus로 정말로 효율적으로 모니터링 매트릭 정보를 수집할 수 있다는 것! Prometheus는 **로그 수집에 최적화** 되어 있다고 과언이 아닙니다.

![prometheus](/img/2019/09/image-1568898356695.png)

이미 MySQL관련하여 Prometheus 기반으로 대규모 모니터링을 하고 있고.. alerting을 위해 자체적으로 구성한 "[pmm-ruled][1]"로 다수의 시스템을 무리없이 이슈 감지하고 있으니, 이것을 시도 안할 이유가 전혀 없습니다. (트래픽은 쥐꼬리만한, 글 몇개 없는 영문 블로그 투척..ㅋㅋ)

참고로 prometheus으로 공식적으로 모니터링을 할 수 있는 exporter들이 이렇게나 많답니다. 써본것은 별로 없지만, 이런 시스템을 새롭게 시작할지라도.. 모니터링에서는 한시름 놓을 수 있겠다는.. -\_-;;  
<https://prometheus.io/docs/instrumenting/exporters/>

# Start! memcached exporter

Prometheus에서는 공식적으로 하단 exporter로 memcached를 모니터링합니다.  
https://github.com/prometheus/memcached_exporter

이렇게 받아서 컴파일을 하면 되고..

```bash
$ go get github.com/prometheus/memcached_exporter
$ cd $GOPATH/src/github.com/prometheus/memcached_exporter/
$ make
$ ls -al memcached_exporter
-rwxr-xr-x  1 gywndi  staff  12507644  9 19 21:11 memcached_exporter
```

바로 이전에 구성을 했던 MySQL InnoDB memcached plugin이 있는 곳을 향하여 exporter를 올려봅니다.

```bash
$ ./memcached_exporter --memcached.address=10.5.5.12:11211
INFO[0000] Starting memcached_exporter (version=, branch=, revision=)  source="main.go:795"
INFO[0000] Build context (go=go1.11.5, user=, date=)     source="main.go:796"
INFO[0000] Starting HTTP server on :9150                 source="main.go:827"
```

# Problem

그런데 문제가 생겼네요.  
`http://10.5.5.101:9150/metrics`에 접근해서, memcached exporter가 수집해서 뿌려주는 metric 정보를 확인해보았는데.. exporter에서 아래와 같은 이상한 에러를 뱉어낸 것이죠. (참고로, exporter를 올린 곳의 아이피는 10.5.5.101입니다.)

```
ERRO[0024] Could not query stats settings: memcache: unexpected stats line format "STAT logger standard error\r\n"  source="main.go:522"
```
심지어 exporter에서는 아래와 같이 `memcached_up` 이 "0"인 상태.. 즉, memcached가 죽어있다는 형태로 데이터를 뿌려줍니다. 모니터링을 위해 붙인 exporter가 memcached 데몬이 늘 죽어있다고 이야기를 하면 큰일날 이야기겠죠. ㅠㅠ
```
# HELP memcached_up Could the memcached server be reached.
# TYPE memcached_up gauge
memcached_up 0
```
MySQL memcached plugin에서 `stats settings` 결과는 아래와 같습니다.

```bash
$ telnet 127.0.0.1 11211
Trying 10.5.5.12...
Connected to 10.5.5.12.
Escape character is '^]'.
stats settings
STAT maxbytes 67108864
STAT maxconns 1000
..skip ..
STAT item_size_max 1048576
STAT topkeys 0
STAT logger standard erro   &lt;-- 이녀석!!
END
```

문제는 저 윗부분에서 4개의 단어로 이루어진 저 부분에서 발생한 문제이지요. memcached exporter에서 `stats settings`을 처리하는 `statusSettingsFromAddr` 함수에서, 결과가 3개의 단어로만 이루어진 것을 정상 패턴으로 인지하고, 그 외에는 무조건 에러로 리턴하는 부분에서 발생한 것인데요.

`[memcache.go][2]` 파일의 가장 하단에 위치한 `statusSettingsFromAddr` 함수 내부의 이 부분이 원인입니다.

```cpp
stats := map[string]string{}
for err == nil && !bytes.Equal(line, resultEnd) {
    s := bytes.Split(line, []byte(" "))
    if len(s) != 3 || !bytes.HasPrefix(s[0], resultStatPrefix) {
        return fmt.Errorf("memcache: unexpected stats line format %q", line)
    }
    stats[string(s[1])] = string(bytes.TrimSpace(s[2]))
    line, err = rw.ReadSlice('\n')
    if err != nil {
        return err
    }
}
```

# Modify code

그래서 이것을 아래와 같이 4글자까지 정상 패턴으로 인지하도록 변경을 했습니다. 물론, 정상 패턴을 3단어로만 했던 원작자의 정확한 의도는 모르지만요.. ㅠㅠ

```cpp
stats := map[string]string{}
for err == nil && !bytes.Equal(line, resultEnd) {
    s := bytes.Split(line, []byte(" "))
    if len(s) == 3 {
        stats[string(s[1])] = string(bytes.TrimSpace(s[2]))
    } else if len(s) == 4 {
        stats[string(s[1])] = string(bytes.TrimSpace(s[2])) + "-" + string(bytes.TrimSpace(s[2]))
    } else {
        return fmt.Errorf("memcache: unexpected stats line format %q", line)
    }
    line, err = rw.ReadSlice('\n')
    if err != nil {
        return err
    }
}
```

이제 컴파일하고, 다시 memcached exporter를 구동해볼까요?

```bash
$ cd $GOPATH/src/github.com/prometheus/memcached_exporter
$ go build .
$ ./memcached_exporter --memcached.address=10.5.5.12:11211
INFO[0000] Starting memcached_exporter (version=, branch=, revision=)  source="main.go:795"
INFO[0000] Build context (go=go1.11.5, user=, date=)     source="main.go:796"
INFO[0000] Starting HTTP server on :9150                 source="main.go:827"
```

문제없이 잘 올라왔고, `http://10.5.5.101:9150/metrics`에 접근해도 정상적으로 memcached 구동 상태를 명확하게 보여주고 있군요.

```
# HELP memcached_up Could the memcached server be reached.
# TYPE memcached_up gauge
memcached_up 1   <-- 요기요기요기
```
# External metric with pmm-admin

PMM을 구성하는 것에 대해서는 이 자리에서 설명하지 않겠습니다.

```bash
$ pmm-admin add external:metrics memcached 10.5.5.101:9150=memcached01 --interval=10s
```

그러면 이런 모양으로 MySQL InnoDB memcached로부터 상태 매트릭 정보를 수집하게 됩니다.  
![external metric](/img/2019/09/image-1568901663693.png)

만약, 추가로 memcached라는 job 이름으로 하나를 더 추가하고 싶다면?? 이렇게 하면 됩니다요.

```bash
$ pmm-admin add external:metrics memcached \
   10.5.5.101:9150=memcached01 \
   10.5.5.102:9150=memcached02 \
   --interval=10s
```

이제부터는 **매 10초마다 memcached 에 접근해서 상태 정보를 수집해서 prometheus에 넣습니다.** 이로써, MySQL memcached plugin을 모니터링하기 위한 데이터 수집단계가 모두 마무리 되었습니다. ㅎㅎ  
prometheus에서 `{ job="memcached" }` 쿼리 결과 매트릭을 활용해서, 초당 get 트래픽 뿐만 아니라, get miss 카운트도 충분히 확인 가능합니다. 이런 것들을 잘 활용한다면.. memcached 데몬의 실시간 모니터링 뿐만 아니라 트래픽 트랜드도 쉽게 확인할 수 있겠네요.

# Conclusion

Grafana로 필요한 그래프를 만들어야하는 단계가 남았지만.. 여기서는 선호도에 따른 내용이라.(사실 저도.. get 오퍼레이션 유입 카운트와.. 히트율 정보.. 단 하나의 모니터링만 해놓은지라;; ㅋㅋㅋ 쓸 얘기가 없네요.)

* memcached plugin으로 모니터링
* MySQL memcached plugin에 맞게 소스 일부 수정
* pmm-admin을 활용하여, 동적으로 exporter 등록 및 데이터 수집

세상에는 널린 지식이 많고.. 쉽게 가져다 쓸 수 있지만. 잘 쓰려면.. 발생하는 문제에도 열린(?) 마음으로 당황하지 말고 접근을 하면.. 진짜 **손 안대고 코를 시원하게 풀 수** 있는 다양한 길이 여기저기 많이 열려 있는 듯 합니다.

참고로 위 이슈는 하단 두 개의 깃헙에서 쪼르고 있습니다. (해줄지는 모르겠지만..ㅠㅠ)  
- https://github.com/prometheus/memcached_exporter/pull/71
- https://github.com/grobie/gomemcache/pull/1

좋은 하루 되세용.