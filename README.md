## 利用Kubernetes内置资源搭建TiDB集群

### 1. 问题域和解决思路

Kubernetes内置了多种资源类型： Deployment， StatefulSet， Job， CronJob， DaemonSet等。这些资源类型可以分别看作是一类任务的抽象：比如Deployment对应大部分无状态任务， StatefulSet对应大部分有状态任务（有状态和无状态的主要区别体现在拓扑状态和存储状态上）。在实际应用中,需要根据业务类型和特点,选择合适的资源类型进行部署. 

TiDB是一款开源分布式NewSQL数据库。它实现了一键水平伸缩，强一致性的多副本数据安全，分布式事务，实时 OLAP 等重要特性。TiDB主要由三个组件构成：
* [PD](https://github.com/pingcap/pd)
* [TiKV](https://github.com/tikv/tikv)
* [TiDB](https://github.com/pingcap/tidb)

具体来说, PD是用来对TiKV进行管理和调度，完成数据分配的大脑，内置了etcd来实现容错。TiKV是底层的分布式键值对数据库，利用Raft协议和RocksDB提供强一致的存储。而TiDB则包含了对外的API，用来接收兼容SQL协议的请求并完成语法分析，语义分析，执行SQL逻辑。

类似Etcd，TiKV和PD拥有很强的状态，可以通过StatefulSet进行部署，将数据存储在持久化存储卷Persistent Volume中。而TiDB无需持久化存储，可以采用Deployment进行部署也可以采用StatefulSet进行部署。

按照文档[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)中的步骤按序启动PD、TiKV和TiDB。在不使用Operator的情况下就需要手动先后创建PD、TiKV和TiDB的StatefulSet。并且为了实现实例间的域名访问，需要创建对应的Headless Service，以及为了存储数据，需要使用StorageClass动态创建PV。

### 2. Manifests 
#### PD
pd-peer-service.yaml中定义了Headless类型的Service pd-peer，用来为PD StatefulSet提供唯一的网络标识，做实例间发现。
```yaml
clusterIP: None
  ports:
  - name: peer
    port: 2380
    protocol: TCP
    targetPort: 2380
  - name: client
    port: 2379
    protocol: TCP
    targetPort: 2379
```
pd-service.yaml中定义了ClusterIP类型的Service pd，用来供给TiDB和TiKV在集群内部访问PD。
```yaml
ports:
  - name: client
    port: 2379
    protocol: TCP
    targetPort: 2379
```
pd-statefulset.yaml定义了PD的StatefulSet，其中在通过环境变量将集群信息注入容器，在命令行执行启动命令。
```yaml
containers:
  - command:
    - /bin/sh
    - -ec
    - |
       HOSTNAME=$(hostname)
       PEERS=""
       for i in $(seq 0 $((${INITIAL_CLUSTER_SIZE} - 1))); do
         PEERS="${PEERS}${PEERS:+,}${SET_NAME}-${i}=http://${SET_NAME}-${i}.${PEER_SERVICE_NAME}:2380"
       done
       echo $HOSTNAME
       echo $PEERS
       echo $SET_NAME
       echo $INITIAL_CLUSTER_SIZE
       /pd-server --name=${HOSTNAME} \
         --data-dir=/var/lib/pd  \
         --client-urls=http://0.0.0.0:2379 \
         --advertise-client-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2379 \
         --peer-urls=http://0.0.0.0:2380 \
         --advertise-peer-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2380 \
         --initial-cluster=${PEERS}
env:
  - name: PEER_SERVICE_NAME
    value: pd-peer
  - name: SERVICE_NAME
    value: pd
  - name: SET_NAME
    value: pd
  - name: INITIAL_CLUSTER_SIZE
    value: "3"
```

#### TiKV
类似地，tikv-peer-service.yaml也是定义了集群中TiKV实例的唯一网络标识，提供实例间的互相发现。
```yaml
clusterIP: None
  ports:
  - name: peer
    port: 20160
    protocol: TCP
    targetPort: 20160
```
类似地，tikv-statefulset.yaml定义了PD的StatefulSet，其中在通过环境变量将集群信息注入容器，在命令行执行启动命令。
```yaml
containers:
  - command:
    - /bin/sh
    - -ec
    - |
       HOSTNAME=$(hostname)
       echo $HOSTNAME
       /tikv-server --addr=0.0.0.0:20160 \
          --advertise-addr=${HOSTNAME}.${HEADLESS_SERVICE_NAME}:20160 \
          --data-dir=/var/lib/tikv \
          --pd=${PD_SERVICE_NAME}:2379
env:
  - name: HEADLESS_SERVICE_NAME
    value: tikv-peer
  - name: PD_SERVICE_NAME
    value: pd.endgame
```

#### TiDB
tidb-service.yaml定义了TiDB的服务，用来供外部MySQL Client进行访问。
```yaml
ports:
  - name: mysql-client
    nodePort: 31279
    port: 4000
    protocol: TCP
    targetPort: 4000
  - name: status
    nodePort: 30842
    port: 10080
    protocol: TCP
    targetPort: 10080
```
tidb-deployment.yaml定义了TiDB的Deployment，同样也是在命令行执行启动命令。
```yaml
containers:
  - command:
    - /bin/sh
    - -ec
    - |
       HOSTNAME=$(hostname)
       echo $HOSTNAME
       /tidb-server --store=tikv \
          --path=${PD_SERVICE_NAME}:2379
image: pingcap/tidb:v2.1.0
imagePullPolicy: IfNotPresent
env:
  - name: PD_SERVICE_NAME
    value: pd.endgame
```

这里也可以使用StatefulSet和Headless Service进行部署，yaml直接参考文件tidb-statefulset.yaml和tidb-peer-service.yaml。

### 3. 验证
使用`make build`命令即可在GKE集群上搭建TiDB集群。待所有实例运行正常以后，可以使用MySQL Client连接TiDB并向其中写入数据。

![](https://github.com/mlycore/TiWork/blob/master/pics/tidb.png)

![](https://github.com/mlycore/TiWork/blob/master/pics/mysql.png)

### 4. 拓展

#### 1. 如何自动创建密码
在TiDB集群启动以后默认是没有密码，所以需要进行设置密码。这个工作同样应该被自动化，考虑采用一个Job进行实现。在创建TiDB实例的时候同时创建tidb-init-job，这个任务会不断尝试去为TiDB设置密码，直到成功结束。
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
        mysql -h ${TIDB_SERVICE_NAME} -P${TIDB_SERVICE_PORT} -uroot -e "source init.sql"
    env:
     - name: TIDB_SERVICE_NAME
       value: tidb.endgame
     - name: TIDB_SERVICE_PORT
       value: "4000"
```

创建密码的脚本如下：
```sql
set password for 'root'@'%' = '123456';
flush privileges;
```
使用命令`kubectl create configmap tidb-init -n endgame --from-file=init.sql`来创建ConfigMap，并将其挂载为Job的卷。

注意：出于安全考虑，更规范的做法是用Secrets保存密码。更进一步，不管是ConfigMap还是Secrets，在使用完毕后要尽快删除，并且在初始密码使用后应当尽快再次修改密码。

### 5. 参考资料

[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)

[TiDB Operator](https://github.com/tidb-operator)
