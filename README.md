## 利用Kubernetes内置资源搭建TiDB集群

### 1. 问题域和解决思路

Kubernetes内置了多种资源类型： Deployment， StatefulSet， Job， CronJob， DaemonSet等。这些资源类型可以分别看作是一类任务的抽象：比如Deployment对应大部分无状态任务， StatefulSet对应大部分有状态任务，有状态和无状态的主要区别体现在拓扑状态和存储状态上。在实际应用中,需要根据业务类型和特点,选择合适的资源类型进行部署. 

TiDB是一款开源分布式NewSQL数据库。它能够提供自由水平扩展和，同时支持OLAP和OLTP业务。它主要由三个组件构成:
* [PD](https://github.com/pingcap/pd)
* [TiKV](https://github.com/tikv/tikv)
* [TiDB](https://github.com/pingcap/tidb)

具体来说, PD是用来对TiKV进行管理和调度，完成数据迁移的大脑，其中内置了etcd实现容错。TiKV是底层的分布式键值对数据库，利用Raft协议和RocksDB提供强一致的存储。而TiDB则包含了对外的API，用来接收兼容SQL协议的请求并完成语法分析，语义分析，SQL优化等(结合MySQL的结构进行对比)和执行SQL逻辑。类似Etcd，TiKV和PD拥有很强的状态， 可以通过StatefulSet进行部署。而TiDB可以采用Deployment进行部署也可以采用StatefulSet进行部署。

按照文档[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)中的步骤按序启动PD、TiKV和TiDB。在不使用Operator的情况下就需要手动先后创建PD、TiKV和TiDB的StatefulSet。同时为了实现实例间的域名访问，需要创建对应的Headless Service，以及为了存储数据，需要使用StorageClass动态创建PV。

### 2. 解决方案
#### PD
pd-peer-service.yaml
```yaml
```
pd-service.yaml
```yaml
```
pd-statefulset.yaml
```yaml
```

这里创建两个Service的好处是可以用来区分，peer用来做PD成员间的互相发现，而Service则用来被TiDB和TiKV进行访问。

#### TiKV
tikv-service.yaml
```yaml
```
tikv-statefulset.yaml
```yaml
```

#### TiDB
tidb-peer-service.yaml
```yaml
```
tidb-service.yaml
```yaml
```
tidb-statefulset.yaml
```yaml
```

这里也可以使用Deployment和Service进行部署，yaml直接参考文件

### 3. 验证
使用MySQL Client连接TiDB并向其中写入数据。
使用`make build`命令即可在GKE集群上搭建TiDB集群。
![]()

### 4. 拓展思考
1. 没有挂载时区
进行分布式一致性同步的重要参考就是时间，在公有云上进行部署的时候可以认为集群中多个节点已经进行了同步了时钟，为了避免镜像内部的时间不一致，所以要把时区信息挂载进去。可以通过HostPath的方式进行挂载。

2. 如何自动创建密码
在TiDB集群启动以后默认是没有密码的，所以需要进行设置密码。这个工作同样应该被自动化，所以采用一个Job进行实现。在创建TiDB实例的时候同时创建TiDB-Init-Job，这个任务会不断尝试去为TiDB设置密码，直到结束。
tidb-init-job.yaml
```yaml
    containers:
      - image: arey/mysql-client:latest
        imagePullPolicy: IfNotPresent
        name: tidb-init-job
        command:
        - "/bin/sh"
        - "-ec"
        - |
           mysql -h ${TIDB_SERVICE_NAME} -P4000 -uroot -e "source init.sql"
        env:
        - name: TIDB_SERVICE_NAME
          value: tidb.endgame
        volumeMounts:
        - name: initsql
          mountPath: /init.sql
          subPath: init.sql
```

创建密码的脚本如下：
```sql
set password for 'root'@'%' = '123456';
flush privileges;
```

3. TiDB-Operator采用的是StatefulSet部署的TiDB，而且对初始化脚本的配置更加细致
在后面了解了TiDB-Operator之后能够明显体会到Operator的细致。就初始化密码脚本而言，Operator借助Helm的模板渲染机制，给了用户两种方案，要么将密码创建为Secret，要么创建初始化脚本。启动的时候同样通过一个Job完成自动设置，而这个设置的脚本也考虑到了root用户和非root用户的场景。

### 5. 参考资料
[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)
