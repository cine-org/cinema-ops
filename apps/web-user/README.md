# web-user

Trang người dùng (Next.js, repo `cinema`: `apps/web-user`), chạy ở ns `cinema`, mở ra ngoài tại `https://staging.cine.io.vn` (staging) và `https://cine.io.vn` (production).

```text
Ingress staging.cine.io.vn ─▶ Service web-user :80 ─▶ pod web-user :3000
trình duyệt ─▶ /runtime-config (đọc API_ORIGIN) ─▶ gọi api ở API_ORIGIN
```

| File                            | Nội dung                                                           |
| ------------------------------- | ------------------------------------------------------------------ |
| `base/deployment.yaml`          | Pod web-user, probe `/healthz`, env từ ConfigMap `web-user-config` |
| `base/service.yaml`             | Service `web-user`, cổng 80 trỏ vào cổng `http` (3000) của pod     |
| `envs/<env>/kustomization.yaml` | Tag image, ConfigMap `web-user-config` của env                     |
| `envs/<env>/ingress.yaml`       | Host và chứng chỉ TLS của env                                      |

## Phải nhớ

- Image build một lần, dùng cho mọi env: URL api không nằm trong image mà lấy lúc chạy. Route `/runtime-config` trả về `window.__APP_CONFIG__` với `apiOrigin` = env `API_ORIGIN`.
- Origin của trang phải có trong `CORS_ORIGINS` của api (`apps/api/envs/<env>/kustomization.yaml`), nếu không trình duyệt chặn request.
- `HOSTNAME=0.0.0.0`: Next.js lắng nghe theo biến này. Kubernetes đặt `HOSTNAME` bằng tên pod, khi đó server chỉ nghe trên IP của pod.
- Tag image do bot bên `cinema` cập nhật sau mỗi lần merge vào `main` (xem [api](../api/README.md), mục Tag image).

## Verify

```bash
kubectl get app web-user -n argocd                      # Synced/Healthy
curl -s https://staging.cine.io.vn/healthz                       # {"status":"ok"}
curl -s https://staging.cine.io.vn/runtime-config                # apiOrigin của env
```
