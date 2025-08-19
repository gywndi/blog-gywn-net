---
title: MySQL_5.7의 n-gram 전문 검색을 이상하지 않게 써보아요.
author: gywndi
type: post
date: 2017-04-18T23:47:31+00:00
url: 2017/04/mysql_57-ngram-ft-se
categories:
  - MySQL
  - Research
tags:
  - MySQL
  - ngram

---
# Overview

MySQL5.6부터는 InnoDB에서도 전문검색이 가능하기는 하였습니다만.. 아쉽게도 여전히 공백 기준으로 단어들이 파싱이 되는 `MeCab Full-Text Parser Plugin` 방식으로 동작합니다. 즉, 한국말처럼 공백만으로 단어를 파싱할 수 없는 언어의 경우에는 크게 매력적이지는 않습니다. **InnoDB에서 전문검색 인덱싱이 가능하다는 것은 Transaction이 전제로 이루어지는 것이라고 볼 수 있기에.. 리플리케이션 및 시점 백업/복구 측면에서는 혁신**으로 볼 수 있습니다.

> **반드시 Limit로 끊어서 가져오고자 한다면, 'Order By'로 정렬을 하세요~ 이 관련해 버그가 있고 조만간 픽스될 예정이기는 합니다. (n-gram 처리 시 스토리지 엔진에서 limit이 영향을 미쳐 제대로된 결과 도출 혹은 최악의 경우 크래시까지 발생할 수 있어요.)**

그런데 MySQL 5.7부터는 InnoDB에서도 n-gram 방식의 전문 검색 인덱스를 지원하면서, 한국어/중국어/일본어에서도 효율적인 전문 검색이 가능하게 되었습니다. 물론 mroonga와 같은 Third party 스토리지 엔진을 설치해서 사용을 할 수 있겠지만.. 백업/복구가 늘 이슈가 늘 따라다니고는 했습니다.

참고로, 전문 검색이란.. LIKE &#8216;%검색어%&#8217; 과 동일한 역할을 한다고 보시면 되겠습니다. (조금 의미는 다르지만.. ㅋ)

# N-GRAM?

자세한 내용은 하단 링크를 쭉 읽오보시면 되겠습니다만..  
https://dev.mysql.com/doc/refman/5.7/en/fulltext-search-ngram.html

간단하게 저 메뉴얼 내용을 인용하자면, 컨텐츠의 인덱스를 아래와 같이 첫글자/두글자..(1그램,2그램,3그램..) 등등으로 나누어서 파싱하여 전문검색 인덱스를 만드는 것이라고 생각하면 되겠습니다.

```
n=1: 'a', 'b', 'c', 'd'
n=2: 'ab', 'bc', 'cd'
n=3: 'abc', 'bcd'
n=4: 'abcd'
```

그리고, 기본적으로 InnoDB에서 제공해주는 ngram의 최소 토큰 사이즈(ngram\_token\_size)는 2이고, 위에서 'n=2' 부터 토큰을 만들게 됩니다. 당연한 이야기겠지만, n-수치가 낮을수록 토큰 수가 많아질 것이기에, 모든 검색어들이 3글자부터 시작된다면 이 수치를 3으로 상향 조정하는 것도 인덱싱 관리 및 사이즈 안정성에 도움이 되겠습니다.

# Simple Test

```sql
mysql> CREATE TABLE `articles` (
    ->  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
    ->  `body` text,
    ->  PRIMARY KEY (`id`),
    ->  FULLTEXT KEY `ftx` (`body`) WITH PARSER ngram
    ->) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
mysql> insert into articles (body) values ('east');
mysql> insert into articles (body) values ('east area');
mysql> insert into articles (body) values ('east job');
mysql> insert into articles (body) values ('eastnation');
mysql> insert into articles (body) values ('eastway, try try');
mysql> insert into articles (body) values ('try try');
```

**'WITH PARSER ngram'** 부분을 명시적으로 적지 않으면, 기존 전문검색 인덱스로 구성되니 유의하시기 바랍니다. 자, 이 상태에서 &#8216;st&#8217;가 들어있는 데이터를 검색해볼까요?

```sql
mysql> SELECT * FROM articles WHERE MATCH(body) AGAINST('st' IN BOOLEAN MODE);
+----+------------------+
| id | body             |
+----+------------------+
|  7 | east area        |
|  6 | east             |
|  8 | east job         |
|  9 | eastnation       |
| 10 | eastway, try try |
+----+------------------+
```

참고로, 위 정렬 순서는 단어 매칭 수가 많은 데이터 순서로 자동 정렬이 됩니다.

# STOPWORD Problem

우연찮게 동료가 자신의 이름을 검색을 하다 발견했던 이슈인데.. 위 상태에서 'ea'를 포함하는 데이터를 검색해봅니다. 분명히 데이터가 존재함에도, 아래와 같이 한 건도 나오지 않는 점을 확인할 수 있습니다.

```sql
mysql> SELECT * FROM articles WHERE MATCH(body) AGAINST('ea' IN BOOLEAN MODE);
Empty set (0.00 sec)

mysql> SELECT * FROM articles WHERE MATCH(body) AGAINST('eas' IN BOOLEAN MODE);
Empty set (0.01 sec)
```

아무래도 5.7에서 새롭게 들어온 n-gram방식이라서 그런지요.INNODB\_FT\_DEFAULT\_STOPWORD에 의존적으로 n-gram 도 동작을 하게 됩니다. 기존 전문검색인덱스에서는 공백 기준으로 토큰화되기 때문에, 영문에서 자주 쓰이는 단어들은 인덱스로 분류되지 않도록 지정을 합니다. 이 단어들이 모여있는 테이블이 바로 information\_schema 에 위치한INNODB\_FT\_DEFAULT_STOPWORD 테이블이죠.

```sql
mysql> SELECT * FROM INFORMATION_SCHEMA.INNODB_FT_DEFAULT_STOPWORD;
+-------+
| value |
+-------+
| a     |
| about |
| an    |
| are   |
| as    |
| at    |
..중략..
| who   |
| will  |
| with  |
| und   |
| the   |
| www   |
+-------+
```

그런데 참 재미있는 것이.. 단어 파싱의 기준은 n-gram으로 하면서, 실제 룰 일부는 기존의 'MeCab' 기준으로 적용한다는 사실이죠. 위 예제에서는 위에 포함이 되어 있는 'a' 단어로 인하여 'east'문자는 'e', 'st' 이렇게 파싱이 되고, 결과적으로 'ea' 검색 결과에서 누락이 되는 상황이 되어버리고 만 것입니다.

`INNODB_FT_DEFAULT_STOPWORD`에 대한 조금더 상세한 얘기는 하단 매뉴얼을 참고하시면 되겠습니다.  
https://dev.mysql.com/doc/refman/5.6/en/fulltext-stopwords.html

# Workaround

현재로서는 `information_schema` 하단에 위치한 이 테이블의 데이터를 조작하거나, 변경할 수 있는 방안은 없습니다.

오라클/Percona에서 어떻게 대응해줄지는 모르겠지만, 일단 당장 이 이슈가 해결될 것 같지는 않기에, 조금 트릭으로 풀어야겠습니다. 그래서 아래와 같이 데이터가 전혀 없는ngram\_stopwords 테이블을 만들고, 이 테이블을INNODB\_FT\_DEFAULT\_STOPWORD 대용으로 사용하겠다고 파라메터 지정하는 것인데요.

```sql
mysql> CREATE TABLE mysql.ngram_stopwords(value VARCHAR(18)) ENGINE = INNODB;
mysql> SET GLOBAL innodb_ft_server_stopword_table='mysql/ngram_stopwords';
```

기존에 이미 n-gram 전문검색인덱스가 존재한다면, 반드시 테이블 재구성을 하시기 바랍니다. (모든 데이터를 다시 파싱을 해야하기 때문이죠.)

```sql
mysql> alter table articles engine = innodb;
```

이제 아까처럼 다시 'ea'로 검색을하면, 아래와 같이 예~쁜 결과가 나오게 됩니다. ^\____^

```sql
mysql> SELECT * FROM articles WHERE MATCH(body) AGAINST('ea' IN BOOLEAN MODE);
+----+------------------+
| id | body             |
+----+------------------+
|  7 | east area        |
|  6 | east             |
|  8 | east job         |
|  9 | eastnation       |
| 10 | eastway, try try |
+----+------------------+
```

단, 이렇게 트릭을 사용한 이상.. 사이드이펙트가 무엇일지 생각을 해봐야겠지요? stopword와 관련된 테이블을 여러개를 가질 수 없다는 점입니다. 즉, MeCab 파서에도 영향을 줄 것이므로, 반드시 이 점 인지시기 바랍니다. ^^ (가장 좋은 해결책은 n-gram 파서 경우에는INNODB\_FT\_DEFAULT_STOPWORD를 적용하지 않는 것일텐데.. ㅎㅎ)

**이 부분은 조만간 Percona 에서는 파라메터로 제어할 수 있도록 해준대요~ 기다리세요. ㅋㅋ**

# Conclusion

역시. 신기능은 조금 기다려야했나.. 버그 이슈로 마음고생 많이 했습니다.

그렇지만.. 어찌어찌 해결이 되었고. 아마도 다음 릴리즈에서는 Percona에서는 픽스해서 GA로 오픈할 듯 하네요. 안정화를 더 해봐야하고, 성능 튜닝도 이루어져야할 것이겠지만.. 점차 좋은 기능들이 InnoDB로 들어오게 되면서, **리플 안정성 및 데이터 백업/복구 측면에서 대단한 발전이 있는 것은 사실**입니다.

물론. Elastic Search와 같은 솔루션으로 해결해볼 수 있겠으나, 적절한 데이터 사이즈에서는 충분히 MySQL의 쿼리캐시(Result Cache)를 같이 조합해보면 대단한 효과를 낼 수 있다고 판단합니다.

데이터는 데이터일뿐.. ㅋㅋ 좋은밤 되세요.^^