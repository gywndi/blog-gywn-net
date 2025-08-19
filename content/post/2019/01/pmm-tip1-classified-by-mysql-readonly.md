---
title: PMM팁1탄! MySQL을 READ-ONLY 기준으로 표기해보기.
author: gywndi
type: post
date: 2019-01-28T23:58:03+00:00
url: 2019/01/pmm-tip1-classified-by-mysql-readonly
categories:
  - MariaDB
  - MySQL
  - PMM
tags:
  - MySQL
  - PMM

---
# Overview

어느덧 1월이 마무리되어가는 이 시점.. 한달 내내 놀다 시간 보내기에는 아쉬움이 많이 남아, 블로그 한두개 정도는 남겨보고자, 아주 간만에 노트북 앞에 앉습니다. 가장 기억 속에 맴도는 주제를 찾던 중, 작년 나름 많은 분석을 했었던 내용들을 한번 몇가지 주제로 정리해보고자 합니다.

**PMM**(**P**ercona **M**onitoring and **M**anagement)이라는 녀석으로 퉁 쳐서 이야기를 했지만, 사실 이번에 이야기할 내용은 Prometheus 쿼리와 Grafana를 사용하는 간단한 꼼수(?)에 대한 이야기입니다.

혹시 PMM이 어떤 녀석인지 궁금하시다면? [PMM 이야기 1편 – INTRO](/2018/03/pmm-intro/) 편을 읽어보주세요. ㅎㅎ

# Definition

이 주제는 MySQL의 READ-ONLY 설정 값에 따른 서버들 표기로 되어 있지만, 제 입장에서는 이는 곧 마스터/슬레이브를 구분하는 주제이기도 합니다. 물론, MySQL을 다양한 토폴로지로 이를테면, (M)-(M/S)-(S)와 같은 체이닝 구조로도 서비스를 운영해볼 수 있겠지만.. 개인적인 생각으로는 다양한 장애를 대비했을 때 가장 간단한 구성이 최고의 강력함을 선사한다고 생각을 하기에.. 제 입장에서 **READ-ONLY가 ON으로 활성화된 녀석을 슬레이브로라고 정의**합니다.

1. **마스터 (READ_ONLY: OFF)** 
   데이터 변경의 주체가 되는 인스턴스  
   (M)-**(M/S)**-(S) 와 같은 중간 체이닝 구조에서 (M/S)는 마스터로 인지
2. **슬레이브 (READ_ONLY: OFF)**  
   데이터 변경이 불가한 인스턴스

개인의 정의에 따라 다르게 쿼리가 나오겠지만, 제가 원하는 그림은, **READ_ONLY가 ON/OFF에 따른 서버 분류** 혹은 **전체 인스턴스 기준**에 따른 표현입니다.

# Grafana Variable

MySQL에서 READ-ONLY는 ON/OFF 정도만을 의미합니다만, 여기서는 전체 서버를 의미하는 값으로 2값을 추가로 의미부여해보았습니다.

  * `var_read_only` : 0 (READ-ONLY OFF)
  * `var_read_only` : 1 (READ-ONLY ON)
  * `var_read_only` : 2 (ALL)

Grafana에서 새로운 Variable을 추가하는 방법은 대시보드의 Setting의 Variables 탭에서 새롭게 추가하는 것으로~ (설명은 패스) 그리고, 아래와 같이 Custom 타입으로 2,0,1로 정의해봅니다. 2가 제일 앞인 이유는.. 그냥 기본 값으로 지정을 해보기 위함이죠.
![Grafana Variable - READ-ONLY](/img/2019/01/grafana-read-only-variable1-1024x495.png)

그런데 문제는, 이렇게 만든 Variable 셀렉트 박스를 보면, 표기가 2,0,1로 보여지고 있어서 직관적이지가 않습니다. `2->ALL`, `0->OFF`, `1->ON`으로 셀렉트 박스에 표현되는 것이 사용상으로 괜찮겠죠? (물론 사용에는 무리가 없지만..)

Grafana의 UI 세팅에서는 불가(아직까지는)한 듯 하고.. 이는 Grafana를 Export한 후 약간 조작 후 다시 Import하는 과정이 필요합니니다. Share Dashboard > Export 탭으로 들어가서 json 파일로 내린 후 열어보면, 아래와 같이 text 부분도 역시 value와 같은 값으로 설정되어있는데,

```
{
  "allValue": null,
  "current": {
    "text": "2",
    "value": "2"
  },
  "hide": 0,
  "includeAll": false,
  "label": "Read-only",
  "multi": false,
  "name": "read_only",
  "options": [
    {
      "selected": true,
      "text": "2",
      "value": "2"
    },
    {
      "selected": false,
      "text": "0", <==
      "value": "0"
    },
    {
      "selected": false,
      "text": "1",
      "value": "1"
    }
  ],
  "query": "2,0,1",
  "type": "custom"
}
```

위 text 붉은 부분을 아래와 같이 직관적인 문구로 바꾸어주고, 해당 Dashboard를 다시 Import해주면~

```
{
  "allValue": null,
  "current": {
    "text": "ALL",
    "value": "2"
  },
  "hide": 0,
  "includeAll": false,
  "label": "Read-only",
  "multi": false,
  "name": "read_only",
  "options": [
    {
      "selected": true,
      "text": "ALL",
      "value": "2"
    },
    {
      "selected": false,
      "text": "OFF", <==
      "value": "0"
    },
    {
      "selected": false,
      "text": "ON",
      "value": "1"
    }
  ],
  "query": "2,0,1",
  "type": "custom"
}
```

최종적으로 Grafana 화면에서 직관적인 문구로 확인이 가능합니다. 쉽게 조작이 어렵다는 점이.. 참으로 서글프네요. 아무튼 첫번째 검색어 세팅 완료!

![Grafana Read-Only Variable Modify](/img/2019/01/grafana-read-only-variable2-1024x510.png)

# Promethues Query

Grafana 에서 원하는 조건대로 전달할 수 있는 기반이 만들었으니, 이번에는 데이터를 조회하는 Prometheus 쿼리를 작성해보도록 하겠습니다. 이 자리에서, Prometheus 쿼리를 하나하나 설명하지는 않을 것으므로, Prometheus 공식 사이트 메뉴얼을 한번씩은 꼭 방문하셔서, 쿼리 구문을 읽어봐 주시와요~ ([Querying Prometheus](https://prometheus.io/docs/prometheus/latest/querying/basics/))

제 관심사는, **READ-ONLY ON/OFF에 따른 그룹핑된 결과물**입니다. 앞선 정의에서, `read_only` 값이 0이면 마스터, `read_only`가 1이면 슬레이브, 그리고 2이면 전체 서버를 의미하는 것으로 이야기를 했었죠. Grafana에서 전달해주는 이 데이터를 기반으로 원하는 데이터들만 선별해서 가져와보도록 하겠습니다.

우선 아래와 같이 `max_over_time`으로 1분간 최대값을 가져오는 Prometheus 쿼리로 현재 시스템 로드를 추출해봅니다. 이는, 전체 인스턴스에 해당하는 결과값들입니다.

```
max_over_time(node_load1[1m])
```

READ-ONLY 상태 값에 대한 조건을 추가하여, READ-ONLY ON/OFF에 해당하는 결과를 조회해봅니다. 여기서 `on (instance)` 항목은 어떤 데이터를 기준으로 데이터 연산을 처리할 것인가를 의미하는데, SQL 기준이라면, 아무래도 JOIN 조건이라고 보면 무관하겠네요.

```
max_over_time(node_load1[1m])
  and on (instance) (mysql_global_variables_read_only == $read_only)
```

그런데 여기서 문제가 하나 생겼습니다. READ-ONLY 값이 존재하는 경우에는 큰 문제없이 쿼리 질의가 되지만, 마스터/슬레이브를 섞어서 한번에 봐야하는 케이스, 즉 전체 서버를 모두 표현하는 경우 정상적으로 쿼리가 동작하지 않는다는 것이죠.

그래서, 여기서 극강의 꼼수 하나를 더 슬그머니 밀어봅니다. ㅋ 세 값의 연산 결과가 2일때만 1 이상이 되는 공식을 만들기만 하면 해결이 될 듯 하죠? 그리고 OR 조건을 묶어서, 우선 연산 처리를 하고, 부합되지 않는 경우 READ-ONLY 부분이 동작하도록 쿼리 작성을 해보도록 한다면..? 각 인스턴스 단위로 무조건 존재하는 메트릭을 손 꼽아 보자면..??

`up{job='linux'}` 값을 이용해볼 수 있겠습니다. 이 값의 결과는 0 또는 1이며, Exporter가 존재하는 한 무조건 존재한다고 가정해볼 수 있습니다. 즉, `$read_only`가 0과 1인 경우 음수로 나오며, 2 이상인 경우에만 1이상의 양수 값이 나오도록 아래와 같이 쿼리를 작성해볼 수 있겠습니다.

```
max_over_time(node_load1[1m])
 and on (instance) (up{job='linux'} <= $read_only^2-3 or mysql_global_variables_read_only == $read_only)
```

이렇게되면, 우선 2인 경우에는 첫번째 up 조건에서 필터링 되면서 뒤의 `mysql_global_variables_read_only` 부분을 참조하지 않습니다. (or는 앞의 결과가 없는 경우 수행) 그러나 만약 `read_only` 필터링 조건이 들어오면서 0 또는 1로 연산이 되면, up 결과는 존재하지 않으므로, `mysql_global_variables_read_only` 값을 체크하면서 최종적으로 원하는 형태로 데이터를 추출해 내는 것이죠.

설명이.. 쿨럭.. 어렵.. (한국말좀 알려주세요. ㅠㅠ) 그래서 준비했습니다. 어떤 결과로 보여지는지..

테스트로 로컬에 VM을 구성해서 아래와 같은 구조로 MySQL 서버를 세팅한 후에 PMM exporter를 띄워보았습니다. node01과 node03은 당연히 데이터 변경의 주체 역할을 가지므로, `read_only`를 OFF로 해놓았고요.

```
node01 : Master
  ㄴ node02 : Slave
node03:  Master(Single)
```

### Case1. ALL Instance

pmm-server 인스턴스를 포함해서 모든 서버들이 모두 보여집니다.

![ALL Server](/img/2019/01/pmm_result_readonly_all-1002x1024.png)

### Case2. READ-ONLY: OFF

의도한대로, READ-ONLY가 OFF인 인스턴스만 모여서 같이 그래프를 보여주죠. 참고로, READ-ONLY 속성을 가지고 있는 mysql 인스턴스 데이터들만 표기해주므로, pmm-server 인스턴스는 대상 리스트에서 빠집니다. (당연한 이야기지요. READ-ONLY 속성으로 조회를 했으니..)

![READ-ONLY OFF](/img/2019/01/pmm_result_readonly_off-999x1024.png)

### Case3. READ-ONLY: ON

마지막으로.. READ-ONLY가 ON인 슬레이브 녀석만 별도로 보여줍니다. 여기서도 역시 pmm-server는 빠집니다.

![READ-ONLY ON](/img/2019/01/pmm_result_readonly_on-997x1024.png)

# Conclusion

사실은 별 것 없습니다. 제게 필요한 정보를 추출해보기 위해서.. 그냥 사소한 고민을 해보았었고, 약간의 꼼수로 필터링을 할 수 있도록 쿼리를 작성한 것 뿐이지요.

제가 한 일이라고는..
1. **Grafana에서 READ-ONLY 표기를 직관적으로 표기하기 위한 대시보드 Import 꼼수** 
2. **2가지 단계(전체, READ-ONLY ON/OFF)로 필터링할 수 있도록 Prometheus 꼼수 쿼리 작성**

이 긴 글에서 위 두 가지 정도로 보여지네요. 허허..;; 그렇기 때문에, 초고수 분들에게는 우스운 포스팅일 수도 있습니다. 그렇지만.. 수십대가 넘어가는 마스터/슬레이브가 섞인 환경에서.. **한눈에 시스템의 리소스 현황을 파악하는 경우.. 롤에 따른 분류가 생각보다 크나큰 의미**가 있습니다. ^^

제 문제 상황에서 해결방안을 고민한 아이디어이며, 더욱 좋은 번뜩이는 아이디어가 있으면 같이 나눴으면 하는 생각으로.. 장기 휴가 후 복귀를 얼마 남겨둔 입장에서 포스팅 하나 날려봅니다.

심심해서, 간단하게 만들어본 [대시보드](https://github.com/gywndi/kkb/blob/master/pmm-dashboard/My_Dashboard.json)를 공유합니다. Grafana에 Import를 해서 직접 보시면 이해가 빠를 듯 하네요.  


PS. 이 예제는 이해를 위해, 가장 기초적인 요건만 고려해서 만든 것입니다. MySQL이 죽어있거나, `mysql_up`이 OFF인 경우, 즉 `read_only` 파라메터가 정상 수집이 되지 않는 경우는 풀 수 있는 난제로 남겨두고 도망갑니다. ㅋ

좋은 밤 되세요. ^^