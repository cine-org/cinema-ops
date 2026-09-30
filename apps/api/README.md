# api

Backend NestJS của repo `cinema` (`apps/api`), chạy ở ns `cinema`, mở ra ngoài tại `https://api.<domain>`.

```text
Ingress api.<domain> ─▶ Service api :80 ─▶ pod api :3000 ─▶ postgres-rw / postgres-r (ns infra)
```

| File                            | Nội dung                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------ |
| `base/deployment.yaml`          | Pod api, probe `/health`, env từ ConfigMap `api-config` và Secret `api-db`     |
| `base/service.yaml`             | Service `api`, cổng 80 trỏ vào cổng `http` (3000) của pod                      |
| `base/external-secrets.yaml`    | Secret `api-db`: `DATABASE_URL` (`cinema_rw`), `DATABASE_URL_RO` (`cinema_ro`) |
| `base/migrate.yaml`             | Job chạy migration bằng role owner `cinema`, trước mỗi lần sync                |
| `envs/<env>/kustomization.yaml` | Tag image, ConfigMap `api-config` của env                                      |
| `envs/<env>/ingress.yaml`       | Host và chứng chỉ TLS của env                                                  |

## Tag image

Image `ghcr.io/cine-org/cinema/api`, tag ghi ở `images[].newTag` trong `envs/<env>/kustomization.yaml`:

- staging: `sha-<7 ký tự commit>`, bot bên `cinema` cập nhật sau mỗi lần merge vào `main`;
- production: `vX.Y.Z`, khi release.

Đổi tag bằng tay cũng chỉ sửa đúng dòng `newTag`. `validate.sh` chặn thiếu tag hoặc tag `latest`.

## Migration

```text
sync ─▶ PreSync: ExternalSecret api-migrate-db (wave -1) ─▶ Job api-migrate ─▶ Deployment api
```

- Job dùng chính image api, chạy `prisma migrate deploy` với role owner `cinema`. Pod api chỉ cầm `cinema_rw`, không tạo/sửa bảng được.
- Job chạy **trước mọi lần sync** của app, kể cả khi chỉ đổi ConfigMap. `migrate deploy` không có migration mới thì không làm gì.
- Job lỗi thì sync dừng, Deployment giữ bản cũ. Xem log: `kubectl logs -n cinema job/api-migrate`.
- `BeforeHookCreation`: Job và ExternalSecret cũ bị xoá ngay trước lần sync sau, nên sau sync vẫn xem được log.
- Migration phải tương thích ngược: bản api cũ còn chạy trong lúc bản mới lên.

## Cấu hình

`configMapGenerator` trong `envs/<env>/kustomization.yaml` sinh ConfigMap tên `api-config-<hash>`. Đổi một giá trị thì hash đổi, Deployment trỏ sang ConfigMap mới và pod tự khởi động lại.

Các biến api đọc: `apps/api/src/config/env.ts` bên repo `cinema`. Biến bí mật đi qua ExternalSecret, không để trong ConfigMap.

## Phải nhớ

- Password Postgres là chuỗi hex nên ghép thẳng vào URL được; password có ký tự đặc biệt thì phải mã hoá URL.
- `DATABASE_URL_RO` trỏ `postgres-r` vì cluster còn 1 instance; `postgres-ro` chỉ đi tới replica ([infra/postgres](../../infra/postgres/README.md)).
- `/health` nằm ngoài prefix `/api`; các route khác ở `/api/v1/...`. Swagger chỉ bật ở staging: `/api/docs`.

## Verify

```bash
kubectl get app api -n argocd                          # Synced/Healthy
kubectl get job,pod -n cinema                          # api-migrate Complete, api Running
kubectl logs -n cinema job/api-migrate
curl -s https://api.<domain>/health                    # {"status":"ok"}
```
