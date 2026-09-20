# Redis: OT-Container-Kit redis-operator

Mục tiêu: một Redis trong namespace `infra` làm cache và bộ đếm rate limit, password từ Google Secret Manager, không ghi đĩa. Khai sẵn theo kiểu bật HA chỉ bằng sửa vài dòng, URL bên app không đổi.

Dùng operator thay vì tự viết StatefulSet, vì phần khó của Redis HA không nằm ở YAML mà ở điều phối: Sentinel bầu master mới, pod khởi động phải tự biết mình là master hay replica, chống hai master cùng nhận ghi, Service phải đi theo master. Operator lo hết, giống CNPG với Postgres.

Không dùng chart Bitnami: từ cuối 2025 Bitnami ngừng phát image miễn phí.

## Cần có trước

- [external-secrets](../external-secrets/README.md) đã chạy, bên GSM đã có `infra-redis` với value `{"password":"<hex>"}`.

## Wiring

```text
clusters/staging/infra/redis.yaml   Application "redis", 2 source:
  ├── chart redis-operator 0.26.1 → ns redis-operator  (helm.releaseName: redis-operator)
  └── infra/redis/envs/staging      → ConfigMap + RedisReplication + ExternalSecret, ns infra
```

`values.yaml` hạ `resources` của chart: mặc định chart xin `500m` CPU và `500Mi` RAM, ngang cả Argo CD. Chart có 4 CRD, mỗi cái 320–520KB, nên `ServerSideApply=true` là bắt buộc.

## File `base/redis.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: infra
data:
  redis-additional.conf: |
    maxmemory 128mb
    maxmemory-policy allkeys-lru
    appendonly no
    save ""
---
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: RedisReplication
metadata:
  name: redis
  namespace: infra
spec:
  clusterSize: 1

  kubernetesConfig:
    image: quay.io/opstree/redis:v8.10.1
    imagePullPolicy: IfNotPresent
    redisSecret:
      name: infra-redis
      key: password
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        memory: 256Mi

  redisConfig:
    additionalRedisConfig: redis-config

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            topologyKey: kubernetes.io/hostname
            labelSelector:
              matchLabels:
                app: redis

  podSecurityContext:
    runAsUser: 1000
    fsGroup: 1000
```

- **`RedisReplication` chứ không phải `Redis`.** Kind `Redis` là bản standalone. Chỉ `RedisReplication` sinh Service `redis-master` luôn trỏ vào master hiện tại. Khai `Redis` thì lúc lên HA phải đổi kind, đổi Service, đổi URL bên app.
- **Không có khối `storage` nên không có PVC**: dữ liệu chỉ nằm trong RAM. Pod restart là cache trống và bộ đếm rate limit về 0, chấp nhận được với hai việc này.
- **`appendonly no` và `save ""` vẫn phải khai** dù không có PVC. Redis 8 mặc định vẫn chụp RDB định kỳ (`save 3600 1 ...`), tức vẫn fork tiến trình và ghi file vào filesystem của container. File ConfigMap được `include` ở cuối `redis.conf` nên đè được mọi dòng image ghi trước đó.
- **`allkeys-lru`**: đầy RAM thì xóa key lâu không dùng. Hợp với cache, và bộ đếm rate limit đang chạy là key vừa dùng nên ít bị xóa. Để `noeviction` thì ngược lại: đầy RAM là `INCR` báo lỗi và rate limit hỏng.
- **`maxmemory` (128mb) thấp hơn hẳn `limits.memory` (256Mi)**: `maxmemory` chỉ tính dữ liệu, chưa tính overhead tiến trình và bộ đệm replication. Để sát nhau là bị OOMKill.
- **Image ghim tag** `v8.10.1`, không dùng `latest` như example của repo operator.
- **`affinity` loại `preferred`**: có nhiều node thì scheduler ưu tiên mỗi pod Redis một node; một node thì vẫn xếp chung được. Không dùng `required` như example của operator, vì trên một node pod thứ hai sẽ `Pending` mãi. Hiện vô hại vì chỉ có một member, khai sẵn để lên HA khỏi phải nhớ.
- `podSecurityContext` chạy non-root, uid 1000.

Image tự thêm `requirepass` và `masterauth` từ `redisSecret`.

## Redis chỉ được giữ thứ mất cũng không sao

Đây là quy ước với bên `cinema`, không phải cấu hình:

- Cache và bộ đếm rate limit: ở Redis, mọi key có TTL.
- Lock ghế: ở **Postgres** bằng unique constraint. Redis replicate bất đồng bộ nên failover có thể làm mất một lock vừa được xác nhận.
- Danh sách thu hồi JWT: ở Postgres.

## Kết nối từ app

| Service (ns `infra`) | Dùng cho |
| --- | --- |
| `redis-master` | đọc và ghi — **app luôn dùng cái này** |
| `redis-replica` | chỉ đọc, có nghĩa khi `clusterSize` > 1 |
| `redis`, `redis-headless`, `redis-additional` | nội bộ operator, app không dùng |

```text
redis://:<password>@redis-master.infra.svc.cluster.local:6379/0
```

## Verify

```bash
kubectl get pods -n redis-operator
kubectl get externalsecret infra-redis -n infra
kubectl get redisreplication -n infra
kubectl get pods,svc,pvc -n infra -l app=redis
```

Xong khi: `externalsecret` là `SecretSynced`, pod `redis-0` Running, có Service `redis-master`, và không có PVC nào tên `redis-redis-*`.

```bash
kubectl get pods -n infra -L redis-role
kubectl get endpointslice -n infra -l kubernetes.io/service-name=redis-master
```

`redis-0` phải mang label `redis-role=master` và là endpoint của `redis-master`. Thiếu label này thì `redis-master` rỗng và app không kết nối được.

Kiểm tra password và config:

```bash
kubectl exec -n infra redis-0 -- redis-cli ping
```

Phải báo `NOAUTH`, chứng minh `requirepass` có hiệu lực. Rồi thử với password:

```bash
PW=$(kubectl get secret infra-redis -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra redis-0 -- env REDISCLI_AUTH="$PW" redis-cli config get maxmemory-policy
kubectl exec -n infra redis-0 -- env REDISCLI_AUTH="$PW" redis-cli config get appendonly
kubectl exec -n infra redis-0 -- env REDISCLI_AUTH="$PW" redis-cli config get save
```

Mong đợi `allkeys-lru`, `no`, và `save` rỗng. Dùng `REDISCLI_AUTH` thay `-a` để password không lộ trong danh sách tiến trình.

## Bật HA về sau

```diff
-  clusterSize: 1
+  clusterSize: 3
+  sentinel:
+    size: 3
+    image: quay.io/opstree/redis-sentinel:v8.10.1
+    resources:
+      requests:
+        cpu: 50m
+        memory: 64Mi
+      limits:
+        memory: 128Mi
+    affinity:
+      podAntiAffinity:
+        preferredDuringSchedulingIgnoredDuringExecution:
+          - weight: 100
+            podAffinityTerm:
+              topologyKey: kubernetes.io/hostname
+              labelSelector:
+                matchLabels:
+                  role: sentinel
```

URL bên app không đổi: Sentinel bầu master mới, operator chuyển label `redis-role=master`, Service `redis-master` đi theo.

Vài điều đã học được khi thử:

- **Chiều ngược lại không tự dọn.** Bỏ khối `sentinel` để về một member thì operator `v0.26.0` chỉ tạo chứ không xóa: StatefulSet `redis-s` và các Service `redis-s*` nằm lại, phải xóa tay.
- **Không khai `resolveHostnames`/`announceHostnames`** dù example của operator có. Ở `v0.26.0`, bật `resolveHostnames: "yes"` thì operator bảo Sentinel theo dõi master bằng hostname nhưng lại không truyền cờ đó xuống pod Sentinel, nên Sentinel từ chối: log operator lặp `ERR Invalid IP address or hostname specified`. Mọi pod vẫn `Running`, replication vẫn chạy, chỉ riêng failover chết.
- **`Running` không chứng minh HA.** Phải hỏi thẳng Sentinel:

  ```bash
  kubectl exec -n infra redis-s-0 -- redis-cli -p 26379 info sentinel
  ```

  Phải thấy `sentinel_masters:1` và dòng `master0:...status=ok,...slaves=2,sentinels=3`. `sentinel_masters:0` nghĩa là Sentinel không theo dõi gì, master chết sẽ không ai bầu lại. Lệnh này không cần password vì ở `v0.26.0` cổng Sentinel nhúng chạy không xác thực.
- **Failover mất khoảng 25 giây** (đo trên staging, `down-after-milliseconds` 5000):

  ```text
  +0s   xóa pod master
  +5s   Sentinel đã chọn master mới, nhưng Service redis-master vẫn trỏ pod cũ
  +14s  redis-master rỗng, không pod nào mang label master
  +29s  operator gắn label, redis-master trỏ master mới; pod cũ lên lại làm replica
  ```

  Phần lớn thời gian là chờ operator reconcile để chuyển label, không phải chờ bầu cử. App phải có retry khi mất kết nối Redis.
- **Chi phí**: 3 Redis khoảng 30Mi và 3 Sentinel khoảng 26Mi lúc rảnh. RAM không đáng kể, cái đắt là thêm pod để trông.
- HA trên một node chỉ chống pod chết, không chống VPS chết.

## Thêm hoặc bỏ storage trên cluster đang chạy

`volumeClaimTemplates` của StatefulSet là bất biến, nên đổi khối `storage` không tự áp được. Phải xóa tay `kubectl delete statefulset redis -n infra` để operator dựng lại, rồi xóa PVC cũ nếu có. Redis gián đoạn khoảng hai phút: pod mới không có dữ liệu nên cùng khởi động làm master, Sentinel còn theo dõi IP cũ, `redis-master` rỗng, operator tự gom lại sau vài nhịp reconcile.

Có annotation `redis.opstreelabs.in/recreate-statefulset` làm việc này tự động, nhưng nó nằm lại vĩnh viễn trên CR: mỗi lần đổi một field bất biến là StatefulSet bị xóa dựng lại.

## Để dành sau

- `redisExporter` cho metrics, bật khi có Prometheus.
- Tách cache và rate limit thành hai instance, nếu cache làm đầy RAM khiến bộ đếm bị xóa.

---

Tiếp: [cert-manager](../cert-manager/README.md).
