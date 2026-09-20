# Hợp đồng với repo `cinema`

> Những gì `cinema-ops` giả định về image bên `cinema`. Cột "Hiện tại" theo trạng thái ngày 2026-09-17.

## Image

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Tên | `ghcr.io/cine-org/cinema/<app>` | đúng |
| Tag deploy | bất biến (version hoặc SHA) | có, kèm `latest` |
| `latest` | không dùng trong manifest | — |
| Non-root | có | **cần kiểm tra** |
| 1 image cho mọi env | cấu hình bằng env lúc chạy | web-user đạt |

Không dùng `latest`: tag không đổi thì Git không đổi, Argo CD không có gì để sync và không rollback được.

Image `setup-monorepo/*:v0.1.0` đang chạy **chưa phải Next.js**, chỉ là nginx phục vụ file tĩnh (~3Mi/pod). `API_ORIGIN` vì thế chưa có tác dụng.

## Các app

| App | Port | Health | Số bản |
| --- | --- | --- | --- |
| `api` | 3000 | `GET /health` | nhiều |
| `web-user` | 80 | `GET /healthz` | nhiều |
| `web-admin` | 80 | **cần thêm** | nhiều |
| `worker` | — | **cần thêm** | nhiều |
| `scheduler` | — | **cần thêm** | **đúng 1** hoặc CronJob |
| `integration` | — | **cần thêm** | — |

Readiness nên kiểm tra kết nối Postgres/Redis.

## Migration

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Chạy ở đâu | Job PreSync, dùng **image api** | image `migrator` riêng — **cần gộp** |
| Lệnh | `prisma migrate deploy` | có |
| Image api cần | `prisma` CLI + thư mục `prisma/` | **cần thêm** |
| Credential | role owner `cinema` | — |
| api tự migrate lúc khởi động | **không** | không |

## Env

| Biến | App | Giá trị |
| --- | --- | --- |
| `DATABASE_URL` | api | `postgresql://cinema_rw:<pw>@postgres-rw.infra.svc:5432/cinema` |
| `DATABASE_URL` | Job migration | `postgresql://cinema:<pw>@postgres-rw.infra.svc:5432/cinema` |
| `REDIS_URL` | api | `redis://:<pw>@redis-master.infra.svc:6379/0` — **chưa có trong schema env** |
| `PORT` | api, web-* | `3000` / `80` |
| `API_ORIGIN` | web-* | `https://api.cine.io.vn` |
| `API_PREFIX` | api, web-user | `/api` / `/api/v1` |
| `CORS_ORIGINS` | api | `https://cine.io.vn,https://admin.cine.io.vn` |

App không đọc `.env` trong cluster. Script `start` phải chạy thẳng `node dist/main`, không `dotenv -e`.

## Đường gọi api

```text
https://cine.io.vn/...              → web-user:80
https://admin.cine.io.vn/...        → web-admin:80
https://api.cine.io.vn/api/v1/...   → api:3000
```

Ingress api **chỉ mở `/api/v1`**:

| Path | Ra Internet |
| --- | --- |
| `/api/v1/...` | có |
| `/api/v1/webhooks/<provider>` | có — api **phải** kiểm chữ ký |
| `/health`, `/api/docs` | không |

- Endpoint nội bộ không đặt dưới `/api/v1`.
- Gọi giữa pod dùng `http://api.cinema.svc:3000`, không vòng qua Ingress.
- Về chung domain sau này chỉ cần sửa env + Ingress (web tự dùng `window.location.origin` khi `API_ORIGIN` trống).
- Ẩn hẳn api thì web phải gọi từ phía server Next.js — sửa code; webhook vẫn cần đường vào.

## Hành vi cần có

- Tự kết nối lại khi mất Postgres/Redis (failover Redis đo được ~25s).
- Tắt êm khi nhận `SIGTERM`.
- Không giữ trạng thái trong pod; upload lên object storage.
- Redis chỉ cache + rate limit, mọi key có TTL, lỗi Redis thì bỏ qua cache.
- Lock ghế ở Postgres (unique constraint + `expires_at`), thu hồi JWT ở Postgres.
- Rate limit đếm atomic (`INCR` + `EXPIRE` trong Lua).
