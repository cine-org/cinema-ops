# web-admin

Trang quản trị (Next.js, repo `cinema`: `apps/web-admin`), chạy ở ns `cinema`, mở ra ngoài tại `https://admin.staging.cine.io.vn` (staging).

```text
Ingress admin.staging.cine.io.vn ─▶ Service web-admin :80 ─▶ pod web-admin :3000
trình duyệt ─▶ /runtime-config (đọc API_ORIGIN) ─▶ gọi api ở API_ORIGIN
```

| File                            | Nội dung                                                             |
| ------------------------------- | -------------------------------------------------------------------- |
| `base/deployment.yaml`          | Pod web-admin, probe `/healthz`, env từ ConfigMap `web-admin-config` |
| `base/service.yaml`             | Service `web-admin`, cổng 80 trỏ vào cổng `http` (3000) của pod      |
| `envs/<env>/kustomization.yaml` | Tag image, ConfigMap `web-admin-config` của env                      |
| `envs/<env>/ingress.yaml`       | Host và chứng chỉ TLS của env                                        |

## Phải nhớ

- Image build một lần, dùng cho mọi env: URL api không nằm trong image mà lấy lúc chạy. Route `/runtime-config` trả về `window.__APP_CONFIG__` với `apiOrigin` = env `API_ORIGIN`.
- Origin của trang phải có trong `CORS_ORIGINS` của api (`apps/api/envs/<env>/kustomization.yaml`), nếu không trình duyệt chặn request.
- `HOSTNAME=0.0.0.0`: Next.js lắng nghe theo biến này. Kubernetes đặt `HOSTNAME` bằng tên pod, khi đó server chỉ nghe trên IP của pod.
- Tag image do bot bên `cinema` cập nhật sau mỗi lần merge vào `main` (xem [api](../api/README.md), mục Tag image).

## Verify

```bash
kubectl get app web-admin -n argocd                      # Synced/Healthy
curl -s https://admin.staging.cine.io.vn/healthz                       # {"status":"ok"}
curl -s https://admin.staging.cine.io.vn/runtime-config                # apiOrigin của env
```
