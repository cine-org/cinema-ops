# redis

Redis chạy bằng operator OT-Container-Kit. Operator ở ns `redis-operator`, Redis ở ns `infra`: 1 member, không ghi đĩa, password lấy từ GSM `infra-redis` (chuỗi trơn). Không dùng chart Bitnami: từ cuối 2025 Bitnami ngừng phát image miễn phí.

Hiện chỉ có `envs/staging`. Production thêm `envs/production` và secret GSM `infra-redis` của project production, merge **trước** release đầu tiên có code dùng Redis.

```text
redis://:<password>@redis-master.infra.svc:6379/0
```

Chỉ giữ cache và bộ đếm rate limit — mất là dựng lại được. Lock ghế và thu hồi JWT để ở Postgres.

## Phải nhớ

- **`RedisReplication`, không phải `Redis`**: chỉ kind này sinh Service `redis-master` luôn trỏ master hiện tại; dùng `Redis` thì lúc lên HA phải đổi kind, Service và URL app.
- Không có khối `storage` → không PVC, dữ liệu trong RAM.
- `appendonly no` + `save ""` **vẫn phải khai**: Redis 8 mặc định chụp RDB định kỳ, vẫn fork và ghi file.
- `allkeys-lru`, không `noeviction`: đầy RAM mà `INCR` lỗi là rate limit hỏng.
- `maxmemory 128mb` < `limits.memory 256Mi`: `maxmemory` chưa tính overhead tiến trình, để sát nhau là OOMKill.
- `affinity` loại `preferred`, không `required` như example của operator — 1 node thì pod thứ 2 `Pending` mãi.
- Chart mặc định xin `500m`/`500Mi`, phải đè bằng `values.yaml`.
- Đổi khối `storage` trên cluster đang chạy: `volumeClaimTemplates` bất biến → `kubectl delete statefulset redis -n infra` cho operator dựng lại, rồi xóa PVC cũ. Gián đoạn ~2 phút.

## Verify

```bash
kubectl get pods,svc,pvc -n infra -l app=redis    # không có PVC redis-redis-*
kubectl get pods -n infra -L redis-role           # redis-0 phải là master
kubectl exec -n infra redis-0 -- redis-cli ping   # phải NOAUTH
```

## HA (để dành sau)

```diff
-  clusterSize: 1
+  clusterSize: 3
+  sentinel:
+    size: 3
+    image: quay.io/opstree/redis-sentinel:v8.10.1
+    resources:
+      requests: {cpu: 50m, memory: 64Mi}
+      limits: {memory: 128Mi}
```

URL app không đổi: Sentinel bầu master, operator chuyển label `redis-role=master`, Service đi theo.

- **Tắt không tự dọn**: bỏ khối `sentinel` thì `v0.26.0` để lại StatefulSet `redis-s` và Service `redis-s*`, phải xóa tay.
- **Không khai `resolveHostnames`** dù example có: `v0.26.0` không truyền cờ xuống pod Sentinel, failover chết mà pod vẫn `Running`.
- **`Running` không chứng minh HA**: `kubectl exec -n infra redis-s-0 -- redis-cli -p 26379 info sentinel` phải thấy `master0:...status=ok,slaves=2,sentinels=3`.
- **Failover ~25s**: bầu xong sau ~5s, phần còn lại chờ operator chuyển label. App phải có retry.
- Chi phí: 3 Redis ~30Mi + 3 Sentinel ~26Mi. Trên 1 node chỉ chống pod chết, không chống VPS chết.
