# Traefik

> Không cài gì. `HelmChartConfig` tên `traefik` ở ns `kube-system` đè values của chart k3s; k3s chạy lại job helm-install để upgrade.

```yaml
spec:
  valuesContent: |
    ports:
      web:
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
              permanent: true
```

- Đặt ở **entrypoint** nên áp cho mọi host, không phải gắn middleware từng Ingress.
- `permanent: true` → 301 với GET, 308 với method khác.
- Không cản cert-manager: Let's Encrypt đi theo redirect.

## Bẫy: sai một cấp khóa

Viết `ports.web.redirections` (thiếu cấp `http`) thì chart 40 **bỏ qua hoàn toàn**: không lỗi, Application vẫn `Synced`, HTTP vẫn 200. Kiểm tra bằng cách hỏi release và pod, không phải grep manifest:

```bash
helm get values traefik -n kube-system
kubectl get pod -n kube-system -l app.kubernetes.io/name=traefik \
  -o jsonpath='{.items[0].spec.containers[0].args}' | tr ',' '\n' | grep -i redirect
```

Phải thấy `--entryPoints.web.http.redirections.entryPoint.to=websecure`.

## Cloudflare

DNS only: Cloudflare chỉ trả IP. Bật proxy thì đặt SSL mode **Full (strict)** và vẫn cần cert-manager. Bản ghi A: `cine.io.vn`, `admin.cine.io.vn`, sau này `api.cine.io.vn`.

## Verify

```bash
curl -sI http://cine.io.vn | head -3     # 301/308 + location https
curl -sI https://cine.io.vn | head -3    # 200
kubectl port-forward -n kube-system deploy/traefik 9000:9000   # dashboard
```

## Để dành sau

nginx cũ có, đây chưa: rate limit, security header, gzip, `client_max_body_size`. Mỗi cái là một `Middleware` gắn vào Ingress.
