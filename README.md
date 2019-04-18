## 利用Kubernetes内置资源搭建TiDB集群

### 1. 问题域和解决思路

Kubernetes内置了多种资源类型: Deployment, StatefulSet, Job, CronJob, DaemonSet等.这些资源类型可以分别看作是一类任务的抽象:比如Deployment对应大部分无状态任务, StatefulSet对应大部分有状态任务.有状态和无状态的主要区别体现在拓扑状态和存储状态上(可以把状态理解为对某个对象的一组描述).在实际应用中,需要根据业务类型和特点,选择合适的资源类型进行部署. 

TiDB是一款开源分布式NewSQL数据库,能够提供自由水平扩展和,同时支持OLAP和OLTP业务。它主要由三个组件构成:
* [PD]()
* [TiKV]()
* [TiDB]()

具体来说, PD是大脑,用来对TiKV进行管理和调度,完成数据迁移的大脑,内置了etcd实现容错. TiKV是底层的分布式键值对数据库,利用Raft协议和RocksDB提供强一致的存储.而TiDB则是对外的API层,用来接收兼容SQL协议的请求,完成语法分析,语义分析,SQL优化等(结合MySQL的结构进行对比)和执行SQL逻辑.其中,类似Etcd,TiKV拥有很强的状态, 需要通过StatefulSet进行部署,而PD和TiDB也一样.

就StatefulSet本身而言,它通过机制能够保证节点间的相关性,比如按顺序启动(或平行启动),能够绑定之前使用的存储卷.这两点解决了有状态应用的网络拓扑和存储状态.

按照文档[link]中的说明,三个组件间启动存在先后顺序,需要先启动PD,再启动TiKV,然后启动TiDB. 在不适用Operator的情况下就需要手动先后创建PD,TiKV和TiDB的StatefulSet.同时为了实现实例间的域名访问,需要创建对应的Headless Service,以及为了存储数据,需要使用StorageClass动态创建PV.

### 2. 解决方案
#### PD
statefulset.yaml
service.yaml

#### TiKV
statefulset.yaml
service.yaml

#### TiDB
deployment.yaml
service.yaml

#### TiDB Init Job
tidb-init-job.yaml

### 3. 验证
使用MySQL Client连接TiDB并向其中写入数据.同时配合可视化工具进行检查,可以观察到有数据流动.
使用Prometheus和Grafana进行监控,在写入数据的同时也能看到CPU和内存指标的变化.
使用e2e测试验证集群的有效性

### 4. 拓展思考
1. 如何自动创建密码
2. TiDB-Operator采用的是StatefulSet部署的TiDB，而且对初始化脚本的配置更加细致
3. 没有挂载时区

### 5. 参考资料
[TiDB on docker](https://pingcap.com/docs-cn/op-guide/docker-deployment/)
