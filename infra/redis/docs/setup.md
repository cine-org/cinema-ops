# Redis (redis-operator)

> Cần `infra-redis` trên GSM. Không dùng chart Bitnami: từ cuối 2025 Bitnami ngừng phát image miễn phí.

Operator ở ns `redis-operator`, Redis ở ns `infra`.

## Phải nhớ

- **`RedisReplication`, không phải `Redis`**: chỉ kind này sinh Service `redis-master` luôn trỏ master hiện tại; dùng `Redis` thì lúc lên HA phải đổi kind, Service và URL app.
- Không có khối `storage` → không PVC, dữ liệu trong RAM.
- `appendonly no` + `save ""` **vẫn phải khai**: Redis 8 mặc định chụp RDB định kỳ, vẫn fork và ghi file.
- `allkeys-lru`, không `noeviction`: đầy RAM mà `INCR` lỗi là rate limit hỏng.
- `maxmemory 128mb` < `limits.memory 256Mi`: `maxmemory` chưa tính overhead tiến trình, để sát nhau là OOMKill.
- `affinity` loại `preferred`, không `required` như example của operator — 1 node thì pod thứ 2 `Pending` mãi.
- Chart mặc định xin `500m`/`500Mi`, phải đè bằng `values.yaml`. 4 CRD lớn → `ServerSideApply=true`.

## Verify

```bash
kubectl get pods,svc,pvc -n infra -l app=redis    # không có PVC redis-redis-*
kubectl get pods -n infra -L redis-role           # redis-0 phải là master
kubectl exec -n infra redis-0 -- redis-cli ping   # phải NOAUTH
```

## Đổi khối storage trên cluster đang chạy

`volumeClaimTemplates` bất biến → `kubectl delete statefulset redis -n infra` cho operator dựng lại, rồi xóa PVC cũ. Gián đoạn ~2 phút.
