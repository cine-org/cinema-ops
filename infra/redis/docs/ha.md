# Redis HA

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

## Đã học được

- **Tắt không tự dọn**: bỏ khối `sentinel` thì `v0.26.0` để lại StatefulSet `redis-s` và Service `redis-s*`, phải xóa tay.
- **Không khai `resolveHostnames`** dù example có: `v0.26.0` không truyền cờ xuống pod Sentinel, log lặp `ERR Invalid IP address or hostname specified`, pod vẫn `Running` nhưng failover chết.
- **`Running` không chứng minh HA**, phải hỏi Sentinel:

  ```bash
  kubectl exec -n infra redis-s-0 -- redis-cli -p 26379 info sentinel
  ```

  Phải thấy `sentinel_masters:1` và `master0:...status=ok,slaves=2,sentinels=3`.
- **Failover ~25s**: bầu xong sau ~5s, phần còn lại chờ operator chuyển label. App phải có retry.
- Chi phí: 3 Redis ~30Mi + 3 Sentinel ~26Mi. Trên 1 node chỉ chống pod chết, không chống VPS chết.
