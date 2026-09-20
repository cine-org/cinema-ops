# Redis (redis-operator)

> Cần `infra-redis` trên GSM. Không dùng chart Bitnami: từ cuối 2025 Bitnami ngừng phát image miễn phí.

Operator ở ns `redis-operator`, Redis ở ns `infra`. Application 2 source: chart + `envs/staging`.

## Điểm phải nhớ trong `base/redis.yaml`

- **`RedisReplication`, không phải `Redis`.** Chỉ kind này sinh Service `redis-master` luôn trỏ master hiện tại; dùng `Redis` thì lúc lên HA phải đổi kind, đổi Service, đổi URL app.
- Không có khối `storage` → không PVC, dữ liệu trong RAM.
- `appendonly no` + `save ""` **vẫn phải khai**: Redis 8 mặc định chụp RDB định kỳ, vẫn fork và ghi file. ConfigMap được `include` cuối `redis.conf` nên đè được.
- `allkeys-lru`: đầy RAM thì xóa key cũ. `noeviction` sẽ làm `INCR` lỗi và rate limit hỏng.
- `maxmemory 128mb` thấp hơn hẳn `limits.memory 256Mi`: `maxmemory` chưa tính overhead tiến trình, để sát nhau là OOMKill.
- `affinity` loại `preferred`, không `required` như example của operator — 1 node thì pod thứ 2 sẽ `Pending` mãi.
- Chart mặc định xin `500m` CPU + `500Mi` RAM, phải đè bằng `values.yaml`. 4 CRD lớn → `ServerSideApply=true`.

## Verify

```bash
kubectl get redisreplication -n infra
kubectl get pods,svc,pvc -n infra -l app=redis        # không có PVC redis-redis-*
kubectl get pods -n infra -L redis-role               # redis-0 phải là master
kubectl exec -n infra redis-0 -- redis-cli ping       # phải NOAUTH
```

```bash
PW=$(kubectl get secret infra-redis -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra redis-0 -- env REDISCLI_AUTH="$PW" redis-cli config get maxmemory-policy
```

Mong đợi `allkeys-lru`. Dùng `REDISCLI_AUTH` thay `-a` để password không lộ trong danh sách tiến trình.

## Đổi khối storage trên cluster đang chạy

`volumeClaimTemplates` bất biến → phải `kubectl delete statefulset redis -n infra` cho operator dựng lại, rồi xóa PVC cũ. Gián đoạn ~2 phút.
