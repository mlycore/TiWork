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
一个软件产品交付给用户之后就正式进入了它的生命周期，相应地TiDB在部署到用户时也开始了它的一生，用户希望它能够友好易用，同时拥有足够的弹性，这就延伸出几个场景：比如一键部署、自动初始化和弹性扩容，下面具体来说：

#### 1. 一键部署
**Helm安装**

Helm提供了强大而灵活的模板渲染能力，让交付部署变得非常简洁和高效。这里的安装操作步骤:
1. 利用`kubectl create ns endgame`创建命名空间
2. 利用`kubectl create configmap tidb-init -n endgame --from-file=helm/tidb/scripts/init.sql`创建初始化密码配置
3. 利用`helm install helm/tidb --name=tidb --namespace=endgame`进行部署
4. 利用`helm del --purge tidb`销毁部署

**Kustomize**

不同于Helm, Kustomize通过类似Sed和Merge的操作，为用户带来了一种简单易用的多版本Yaml定制和管理体验。示例操作步骤:
1. 利用`kubectl create ns endgame`创建命名空间
2. 利用`kubectl create configmap tidb-init -n endgame --from-file=kustomize/scripts/init.sql`创建初始化密码配置
3. 利用`kustomize build kustomize/overlays/dev | kubectl apply -f -`进行部署
4. 利用`kustomize build kustomize/overlays/dev | kubectl delete -f -`销毁部署

#### 2. 自动初始化（以自动创建密码为例）
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

#### 3. 弹性扩容 
首先用户在创建集群的时候需要设置集群初始化大小，这个借助于Helm的`Values.pd.initialsize`、`Values.pd.replicas`、`Values.tikv.replicas`和`Values.tidb.replicas`可以实现。

当集群遇到扩容的需要时，需要通过修改StatefulSet的replicas字段来调整副本数，需要注意的两点：一是建议逐个增加节点，二是扩容的启动参数不同于新建集群的启动参数。所以修改PD StatefulSet的启动脚本为：

```yaml
  containers:
    - command:
      - /bin/sh
      - -ec
      - |
        HOSTNAME=$(hostname)
        echo "hostname"  ${HOSTNAME}
        SET_ID=$(echo ${HOSTNAME} | cut -d"-" -f2)
        echo "set id" ${SET_ID}
        if [ "${SET_ID}" -ge ${INITIAL_CLUSTER_SIZE} ]; then
            echo "Adding new member"
            exec /pd-server --name=${HOSTNAME} \
              --data-dir=/var/lib/pd  \
              --client-urls=http://0.0.0.0:2379 \
              --advertise-client-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2379 \
              --peer-urls=http://0.0.0.0:2380 \
              --advertise-peer-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2380 \
              --join=http://pd-0.${PEER_SERVICE_NAME}:2379
        fi
        echo "Initial starting"
        PEERS=""
          for i in $(seq 0 $((${INITIAL_CLUSTER_SIZE} - 1))); do
              PEERS="${PEERS}${PEERS:+,}${SET_NAME}-${i}=http://${SET_NAME}-${i}.${PEER_SERVICE_NAME}:2380"
          done
        /pd-server --name=${HOSTNAME} \
            --data-dir=/var/lib/pd  \
            --client-urls=http://0.0.0.0:2379 \
            --advertise-client-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2379 \
            --peer-urls=http://0.0.0.0:2380 \
            --advertise-peer-urls=http://${HOSTNAME}.${PEER_SERVICE_NAME}:2380 \
            --initial-cluster=${PEERS}
```
除PD以外，TiKV和TiDB无需调整启动参数。在操作的时候可以通过`kubectl scale`完成增加副本数，也可以通过helm命令实现，比如`helm upgrade --set pd.replicas=4 tidb helm/tidb`。

面对缩容的情况时，重点需要解决节点注销的问题，要么通过PreStop钩子实现，要么可以使用ValidatingAdmissionWebhook来间接实现。同样下面列出PD的注销脚本：
```yaml
lifecycle:
  preStop:
    exec:
      command:
      - /bin/sh
      - -ec
      - |
         HOSTNAME=$(hostname)
         /pd-ctl -u http://pd-0.${PEER_SERVICE_NAME}:2379 -d member delete name ${HOSTNAME} 
         sleep $((RANDOM % 10))
```

注意：
1. 启动脚本中不能使用'#'进行注释，否则后续的命令无法生效
2. PD优雅停止的时候在容器里手动执行删除节点命令能够正常删除，但是通过PreStop或者ValidatingAdmissionWebhook都无法正常删除，这个问题还在检查
3. TiKV缩容的时候需要先对PD执行`store delete`命令，这个暂时没有通过PreStop实现 

### 5. 参考资料

[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)

[TiDB Operator](https://github.com/tidb-operator)

[TiDB 集群扩容缩容方案](https://pingcap.com/docs-cn/op-guide/horizontal-scale/)

[ansible-deployment-scale](https://github.com/pingcap/docs/blob/master/op-guide/ansible-deployment-scale.md)
