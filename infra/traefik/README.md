# traefik

Traefik là cổng vào từ Internet, cài sẵn cùng k3s. Thư mục này không cài chart nào: nó chỉ ghi đè values của chart Traefik mà k3s cài, bằng `HelmChartConfig` tên `traefik` ở ns `kube-system`.

Hiện chỉ đổi một điều: mọi request HTTP được chuyển sang HTTPS, áp cho mọi host.

```text
trình duyệt ─▶ DNS ─▶ :443 VPS ─▶ Traefik (giải mã TLS) ─▶ Service ─▶ Pod
```

## Phải nhớ

- Khoá phải là `ports.web.http.redirections`. Viết thiếu cấp `http` thì chart bỏ qua mà không báo lỗi: app vẫn `Synced`, HTTP vẫn trả 200. Kiểm tra bằng tham số của pod (mục Verify), không kiểm tra bằng manifest.
- `permanent: true`: trả 301 với GET, 308 với các method khác.
- k3s tự cài lại Traefik khi `HelmChartConfig` đổi; nâng k3s có thể nâng chart Traefik, xem lại values khi đó.
- Chưa có: rate limit, security header, gzip, giới hạn body. Mỗi thứ là một `Middleware` gắn vào Ingress.

## Verify

```bash
kubectl get pod -n kube-system -l app.kubernetes.io/name=traefik \
  -o jsonpath='{.items[0].spec.containers[0].args}' | tr ',' '\n' | grep -i redirect
curl -sI http://<host> | head -3     # 301 hoặc 308, location https://
```

Phải thấy `--entryPoints.web.http.redirections.entryPoint.to=websecure`.
