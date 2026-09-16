# Hợp đồng giữa `cinema` và `cinema-ops`

Những gì `cinema-ops` giả định về image của repo `cinema`. Đổi một dòng ở đây là phải sửa cả hai repo.

Cột "Hiện tại" ghi đúng trạng thái repo `cinema` ngày 2026-09-17; chỗ ghi **cần sửa** là việc phải làm bên đó trước khi deploy.

## Image

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Registry + tên | `ghcr.io/cine-org/cinema/<app>` | đúng (`docker-build-push` ghép `registry/owner/repo/app`) |
| Tag deploy | tag bất biến (version hoặc SHA commit) | có, kèm `latest` |
| `latest` | chỉ để người đọc, **không** dùng trong manifest | — |
| Chạy non-root | có | **cần kiểm tra** |
| Một image cho mọi môi trường | cấu hình qua env lúc chạy, không build riêng theo môi trường | web-user đạt (đọc `API_ORIGIN` qua route `runtime-config`) |

Tag `latest` không dùng vì Argo CD so Git: tag không đổi thì Git không đổi, không có gì để sync, và không rollback được.

## Các app

| App | Loại | Port | Health | Số bản chạy |
| --- | --- | --- | --- | --- |
| `api` | Deployment | `3000` (`PORT`) | `GET /health` | nhiều |
| `web-user` | Deployment | `80` (`PORT`) | **cần thêm** | nhiều |
| `web-admin` | Deployment | `80` | **cần thêm** | nhiều |
| `worker` | Deployment | không mở | **cần thêm** | nhiều |
| `scheduler` | Deployment | không mở | **cần thêm** | **đúng 1** (hoặc chuyển sang CronJob) |
| `integration` | Deployment | không mở | **cần thêm** | — |

`/health` hiện luôn trả `ok`, dùng được làm liveness. Readiness nên kiểm tra kết nối Postgres/Redis để pod chưa sẵn sàng không nhận request.

App không mở port vẫn cần cách báo sống (file, port nội bộ, hoặc chấp nhận chỉ dựa vào process còn chạy).

## Migration

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Chạy ở đâu | Job PreSync của Argo CD, dùng **image api** | đang là image `migrator` riêng — **cần gộp vào api** |
| Lệnh | `prisma migrate deploy` | có trong image `migrator` |
| Cần trong image api | `prisma` CLI + thư mục `prisma/` ở stage runtime | **cần thêm** |
| Credential | role owner `cinema` | — |
| api tự migrate lúc khởi động | **không** | không |

## Biến môi trường

`cinema-ops` cấp qua Secret (ExternalSecret từ GSM) hoặc giá trị thường trong manifest. App **không** đọc file `.env` khi chạy trong cluster.

| Biến | App | Giá trị trên cluster | Hiện tại |
| --- | --- | --- | --- |
| `DATABASE_URL` | api | `postgresql://cinema_rw:<pw>@postgres-rw.platform.svc:5432/cinema` | có |
| `DATABASE_READ_URL` | api | `postgresql://cinema_ro:<pw>@postgres-r.platform.svc:5432/cinema` | chưa dùng, để sau |
| `DATABASE_URL` | Job migration | `postgresql://cinema:<pw>@postgres-rw.platform.svc:5432/cinema` | — |
| `REDIS_URL` | api (cache, rate limit) | `redis://:<pw>@redis-master.platform.svc:6379/0` | **chưa có trong schema env** |
| `PORT` | api, web-* | `3000` / `80` | có |
| `API_ORIGIN` | api, web-user | `https://api-staging.cine.io.vn` | có |
| `API_PREFIX` | api, web-user | `/api` (api), `/api/v1` (web-user) | có |
| `CORS_ORIGINS` | api | `https://staging.cine.io.vn,https://admin-staging.cine.io.vn` | có |
| `ENABLE_SWAGGER`, `LOG_LEVEL`, `NODE_ENV` | api | theo môi trường | có |

Password hex (không ký tự đặc biệt) nên ghép thẳng vào URL không cần encode.

Script `start` hiện gọi `dotenv -e ../../.env` — trong image phải chạy thẳng `node dist/main` (Dockerfile đang làm đúng) để env của pod không bị file đè.

## Hành vi app cần có

- **Tự kết nối lại** khi mất Postgres/Redis — failover Redis đo được ~25s không ghi được.
- **Tắt êm khi nhận `SIGTERM`**: ngừng nhận request mới, xử lý nốt, đóng kết nối.
- **Không giữ trạng thái trong pod**: file upload lên object storage, không ghi đĩa pod.
- **Redis chỉ giữ cache và bộ đếm rate limit** — mất là dựng lại được. Mọi key có TTL. Lỗi Redis thì bỏ qua cache, không trả lỗi cho người dùng.
- **Lock ghế ở Postgres** (unique constraint + `expires_at`), không ở Redis.
- **Rate limit đếm atomic** (`INCR` + `EXPIRE` trong Lua, hoặc storage Redis của `@nestjs/throttler`).
- **Thu hồi JWT** (nếu có) lưu ở Postgres.

## Luồng ra image mới

Chưa làm. Hướng đã chọn: CI của `cinema` build + push image, rồi GitHub App `cinema-release-bot` sửa tag trong `cinema-ops`; Argo CD thấy commit mới thì sync.
