# Apps

App của repo `cinema` chạy trong namespace `cinema`. Mỗi app một thư mục, và ApplicationSet trong `clusters/staging/apps.yaml` tự sinh Application cho từng thư mục.

| App | Domain | Trạng thái |
| --- | --- | --- |
| [web-user](web-user/README.md) | `cine.io.vn` | đang chạy |
| [web-admin](web-admin/README.md) | `admin.cine.io.vn` | đang chạy |
| api | `api.cine.io.vn` | chưa dựng |
| worker, scheduler, integration | không mở port | chưa dựng |

Nửa sau file này là **hợp đồng** giữa hai repo: những gì `cinema-ops` giả định về image bên `cinema`. Đổi một dòng ở đây là phải sửa cả hai repo.

## Cấu trúc một app

```text
apps/<app>/
├── base/                    phần chung mọi môi trường
│   ├── deployment.yaml      image không có tag, không có env riêng của env
│   ├── service.yaml
│   └── kustomization.yaml
└── envs/staging/
    ├── kustomization.yaml   images.newTag + patch
    ├── deployment-patch.yaml  env: API_ORIGIN, API_PREFIX
    └── ingress.yaml         domain + chứng chỉ
```

Vì sao chia như vậy: những gì đổi theo môi trường thì nằm ở `envs/`. Tag image, domain và biến môi trường đều thuộc loại đó. Ingress nằm hẳn trong `envs/` vì nó gắn chặt với domain.

Đổi phiên bản đang chạy chỉ là sửa một dòng:

```yaml
# apps/web-user/envs/staging/kustomization.yaml
images:
  - name: ghcr.io/cine-org/setup-monorepo/web-user
    newTag: v0.1.0
```

Đây cũng là dòng mà `cinema-release-bot` sẽ sửa tự động về sau.

## Hợp đồng với repo `cinema`

Cột "Hiện tại" ghi trạng thái repo `cinema` ngày 2026-09-17; chỗ ghi **cần sửa** là việc phải làm bên đó.

### Image

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Registry và tên | `ghcr.io/cine-org/cinema/<app>` | đúng |
| Tag deploy | tag bất biến: version hoặc SHA commit | có, kèm `latest` |
| `latest` | chỉ để người đọc, **không** dùng trong manifest | — |
| Chạy non-root | có | **cần kiểm tra** |
| Một image cho mọi môi trường | cấu hình bằng env lúc chạy, không build riêng theo môi trường | web-user đạt |

Không dùng `latest` vì Argo CD so Git: tag không đổi thì Git không đổi, không có gì để sync, và không rollback được.

Image `setup-monorepo/*:v0.1.0` đang chạy trên staging **chưa phải Next.js**, nó là nginx phục vụ file tĩnh, mỗi pod khoảng 3Mi RAM. Vì vậy `API_ORIGIN` hiện chưa có tác dụng, và con số RAM đo được không đại diện cho pod Next.js thật (ước chừng 60–150Mi mỗi pod).

### Các app

| App | Loại | Port | Health | Số bản chạy |
| --- | --- | --- | --- | --- |
| `api` | Deployment | `3000` (`PORT`) | `GET /health` | nhiều |
| `web-user` | Deployment | `80` (`PORT`) | `GET /healthz` | nhiều |
| `web-admin` | Deployment | `80` | **cần thêm** | nhiều |
| `worker` | Deployment | không mở | **cần thêm** | nhiều |
| `scheduler` | Deployment | không mở | **cần thêm** | **đúng 1**, hoặc chuyển sang CronJob |
| `integration` | Deployment | không mở | **cần thêm** | — |

`/health` hiện luôn trả `ok`, dùng làm liveness được. Readiness nên kiểm tra kết nối Postgres và Redis, để pod chưa sẵn sàng thì không nhận request.

App không mở port vẫn cần cách báo sống: ghi file, mở một port nội bộ, hoặc chấp nhận chỉ dựa vào việc tiến trình còn chạy.

### Migration

| | Quy ước | Hiện tại |
| --- | --- | --- |
| Chạy ở đâu | Job PreSync của Argo CD, dùng **image api** | đang là image `migrator` riêng — **cần gộp vào api** |
| Lệnh | `prisma migrate deploy` | có trong image `migrator` |
| Cần trong image api | `prisma` CLI và thư mục `prisma/` ở stage runtime | **cần thêm** |
| Credential | role owner `cinema` | — |
| api tự migrate lúc khởi động | **không** | không |

### Biến môi trường

`cinema-ops` cấp qua Secret (từ Google Secret Manager) hoặc giá trị thường trong manifest. App **không** đọc file `.env` khi chạy trong cluster.

| Biến | App | Giá trị trên cluster | Hiện tại |
| --- | --- | --- | --- |
| `DATABASE_URL` | api | `postgresql://cinema_rw:<pw>@postgres-rw.infra.svc:5432/cinema` | có |
| `DATABASE_READ_URL` | api | `postgresql://cinema_ro:<pw>@postgres-r.infra.svc:5432/cinema` | chưa dùng |
| `DATABASE_URL` | Job migration | `postgresql://cinema:<pw>@postgres-rw.infra.svc:5432/cinema` | — |
| `REDIS_URL` | api | `redis://:<pw>@redis-master.infra.svc:6379/0` | **chưa có trong schema env** |
| `PORT` | api, web-* | `3000` / `80` | có |
| `API_ORIGIN` | web-user, web-admin | `https://api.cine.io.vn` | có |
| `API_PREFIX` | api, web-user | `/api` (api), `/api/v1` (web) | có |
| `CORS_ORIGINS` | api | `https://cine.io.vn,https://admin.cine.io.vn` | có |
| `ENABLE_SWAGGER`, `LOG_LEVEL`, `NODE_ENV` | api | theo môi trường | có |

Password sinh bằng hex nên ghép thẳng vào URL, không cần encode.

Script `start` bên `cinema` gọi `dotenv -e ../../.env`; trong image phải chạy thẳng `node dist/main` để env của pod không bị file đè. Dockerfile hiện đang làm đúng.

### Đường gọi api

Code chạy trong trình duyệt gọi api, mà trình duyệt không phân giải được tên `*.svc`, nên api phải tới được từ Internet. Mỗi app một subdomain, giống nginx cũ:

```text
https://cine.io.vn/...              → Service web-user:80
https://admin.cine.io.vn/...        → Service web-admin:80
https://api.cine.io.vn/api/v1/...   → Service api:3000
```

**Thu hẹp:** Ingress của api chỉ mở path `/api/v1`. Ngoài path đó thì không ra Internet.

| Path | Ra Internet | Ghi chú |
| --- | --- | --- |
| `/api/v1/...` | có | trình duyệt gọi |
| `/api/v1/webhooks/<provider>` | có | nhà cung cấp gọi vào; api **phải** kiểm chữ ký, không dựa vào việc path bị ẩn |
| `/health` | không | chỉ kubelet gọi |
| `/api/docs` | không | xem qua `kubectl port-forward` |

- Quy ước bên `cinema`: endpoint nội bộ **không** đặt dưới `/api/v1`; webhook đặt dưới `/api/v1/webhooks/`.
- Gọi giữa các pod trong cluster dùng tên nội bộ `http://api.cinema.svc:3000`, không đi vòng qua Ingress.
- Đổi sang chung một domain về sau chỉ cần sửa env và Ingress, không sửa code: web tự dùng `window.location.origin` khi `API_ORIGIN` trống.
- Ẩn hẳn api khỏi Internet thì web phải gọi api từ phía server Next.js, tức sửa code bên `cinema`; webhook vẫn phải có đường vào.
- Sau này có thể tách Ingress riêng cho `/api/v1/webhooks` để gắn middleware khác: không rate limit, chặn theo IP nhà cung cấp.

### Hành vi app cần có

- **Tự kết nối lại** khi mất Postgres hoặc Redis; failover Redis đo được khoảng 25 giây không ghi được.
- **Tắt êm khi nhận `SIGTERM`**: ngừng nhận request mới, xử lý nốt, đóng kết nối.
- **Không giữ trạng thái trong pod**: file upload đẩy lên object storage, không ghi đĩa pod.
- **Redis chỉ giữ cache và bộ đếm rate limit**, mọi key có TTL. Lỗi Redis thì bỏ qua cache, không trả lỗi cho người dùng.
- **Lock ghế ở Postgres** bằng unique constraint và `expires_at`, không ở Redis.
- **Rate limit đếm atomic**: `INCR` kèm `EXPIRE` trong Lua, hoặc storage Redis của `@nestjs/throttler`.
- **Thu hồi JWT** (nếu có) lưu ở Postgres.

## Để dành sau

- **Deploy api**: Ingress `api.cine.io.vn` chỉ mở `/api/v1`, thêm bản ghi DNS, cộng Job migration PreSync.
- **`podAntiAffinity` và PodDisruptionBudget** cho web, có nghĩa khi có node thứ hai.
- **Luồng ra image mới**: CI của `cinema` build và push, `cinema-release-bot` sửa `newTag` trong repo này, Argo CD sync.
- **Xóa `infrastructure/nginx`** bên `cinema`, vì Traefik đã thay nó.
