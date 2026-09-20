# cinema-ops

Mọi thứ chạy trên cluster của dự án `cinema` đều khai báo ở repo này. Argo CD đọc repo, cluster tự khớp theo. Muốn đổi gì trên cluster thì sửa file ở đây rồi push, không SSH vào VPS gõ lệnh.

Repo code nằm ở `cine-org/cinema`. Repo này không chứa code, chỉ chứa cách chạy code đó.

## Hệ thống đang có gì

```text
                        Internet
                           │  DNS Cloudflare (DNS only): cine.io.vn, admin.cine.io.vn
                           ▼
┌──────────────────────── VPS (1 node k3s) ─────────────────────────────────────────┐
│                                                                                    │
│  CỬA VÀO   Traefik (k3s có sẵn)   :80 → 301 https   :443 TLS                       │
│            chứng chỉ: cert-manager xin Let's Encrypt, tự gia hạn                   │
│                           │                                                        │
│  APP       ns cinema      ▼                                                        │
│            Ingress cine.io.vn ─────► web-user                                      │
│            Ingress admin.cine.io.vn ► web-admin                                    │
│            image private trên GHCR, kéo bằng Secret ghcr-pull                      │
│                                                                                    │
│  DỮ LIỆU   ns infra                                                                │
│            Postgres (CNPG)   database cinema, role cinema / cinema_rw / cinema_ro  │
│            Redis (operator)  cache + bộ đếm rate limit, không ghi đĩa              │
│                                                                                    │
│  BÍ MẬT    External Secrets ──► Google Secret Manager                              │
│            password thật không bao giờ nằm trong Git                               │
│                                                                                    │
│  ĐIỀU KHIỂN Argo CD: root-staging đọc clusters/staging/, mọi thứ còn lại từ Git     │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Vòng lặp GitOps: sửa YAML → push lên `main` → Argo CD tự apply. Sửa tay trên cluster thì Argo CD kéo về lại như Git (`selfHeal`). Xóa file khỏi Git thì Argo CD xóa khỏi cluster (`prune`).

## Bản đồ thư mục

```text
README.md            file này
CHEATSHEET.md        lệnh hay dùng và bài tập để hiểu GitOps

bootstrap/           chạy tay đúng 1 lần, trước khi Argo CD tồn tại
├── README.md        VPS: user, SSH, firewall, swap, cài k3s
├── argocd.md        cài Argo CD, credential đọc repo, apply root
└── argocd/          values Helm của Argo CD + root-application.yaml

clusters/staging/    staging chạy những gì
├── infra/           1 Application cho mỗi feat hạ tầng
└── apps.yaml        ApplicationSet: tự sinh Application cho mọi app

infra/<feat>/        hạ tầng dùng chung
├── README.md        khái niệm, vì sao chọn, cách kiểm tra
├── values.yaml      values Helm (nếu feat đó cài chart)
├── base/            manifest chung cho mọi môi trường
└── envs/staging/    phần riêng của staging

apps/                app của repo cinema
├── README.md        hợp đồng giữa cinema và cinema-ops
└── <app>/base + envs/staging
```

Ba tầng trả lời ba câu khác nhau:

| Thư mục | Trả lời câu | Ai apply |
| --- | --- | --- |
| `bootstrap/` | làm sao có cluster và Argo CD | người, 1 lần |
| `clusters/<env>/` | môi trường này chạy những gì | Argo CD (root) |
| `infra/`, `apps/` | từng thứ được khai báo ra sao | Argo CD |

## Quy ước

**Mỗi feat một thư mục.** Cài chart, khai custom resource và lấy secret của cùng một thứ đều nằm chung một chỗ. Ví dụ Postgres: chart CNPG khai trong `clusters/staging/infra/postgres.yaml`, còn `Cluster` và `ExternalSecret` nằm trong `infra/postgres/`.

**Thư mục nào có `base/` thì do Argo CD quản lý** và có đúng một Application cùng tên trong `clusters/staging/infra/`. Ngoại lệ duy nhất là `infra/tailscale/`: hiện chỉ có tài liệu, vì Tailscale đang chạy trên máy chứ chưa chạy trong cluster.

**Argo CD luôn trỏ vào `envs/<env>`, không bao giờ trỏ thẳng vào `base/`.** `base/` giữ phần chung, `envs/staging/` giữ phần riêng: tag image, domain, số bản chạy, dung lượng đĩa.

**Application dùng nhiều source khi feat vừa có chart vừa có manifest:**

```yaml
sources:
  - repoURL: https://charts.example.io      # chart
    chart: something
    targetRevision: 1.2.3
    helm:
      valueFiles:
        - $values/infra/<feat>/values.yaml
  - repoURL: https://github.com/cine-org/cinema-ops.git
    targetRevision: main
    path: infra/<feat>/envs/staging          # manifest
    ref: values                              # để $values ở trên trỏ về gốc repo này
```

**Mọi Application đều có `ServerSideApply=true` và `retry`.** Thiếu `ServerSideApply` thì chart nào kèm CRD lớn (external-secrets, CNPG, cert-manager) sẽ sync fail, vì Argo CD mặc định nhét cả manifest vào annotation `last-applied-configuration` và vượt trần 262144 byte. Thiếu `retry` thì lần dựng đầu tiên phải vào UI bấm Sync tay, vì Application dùng CRD của Application khác sẽ fail nhịp đầu và `selfHeal` không chạy lại một operation đã fail.

**Custom resource của operator mang `sync-wave: "1"`.** Annotation này đặt trong `base/kustomization.yaml`. Nó bắt Argo CD chờ chart (CRD, webhook) ở wave 0 khỏe rồi mới apply `Cluster`, `RedisReplication`, `ClusterIssuer`.

**Thêm app mới:** tạo `apps/<tên>/base` và `apps/<tên>/envs/staging`, push. ApplicationSet tự sinh Application, không phải viết tay.
**Thêm feat hạ tầng mới:** tạo `infra/<tên>/` và một file Application trong `clusters/staging/infra/`.

## Dựng lại từ đầu

Thứ tự này là runbook, làm từ trên xuống. Mỗi file tự đủ, không cần đọc file khác.

| # | Làm gì | Đọc |
| --- | --- | --- |
| 1 | VPS và k3s | [bootstrap/README.md](bootstrap/README.md) |
| 2 | Argo CD và root application | [bootstrap/argocd.md](bootstrap/argocd.md) |
| 3 | Namespace | [infra/namespaces/README.md](infra/namespaces/README.md) |
| 4 | Secret từ Google Secret Manager | [infra/external-secrets/README.md](infra/external-secrets/README.md) |
| 5 | Postgres | [infra/postgres/README.md](infra/postgres/README.md) |
| 6 | Redis | [infra/redis/README.md](infra/redis/README.md) |
| 7 | Chứng chỉ TLS | [infra/cert-manager/README.md](infra/cert-manager/README.md) |
| 8 | Traefik: đường vào, chuyển HTTP sang HTTPS | [infra/traefik/README.md](infra/traefik/README.md) |
| 9 | Kéo image private từ GHCR | [infra/ghcr-pull/README.md](infra/ghcr-pull/README.md) |
| 10 | Chạy web-user và web-admin | [apps/README.md](apps/README.md) |

Tham khảo thêm: [clusters/staging/README.md](clusters/staging/README.md) mô tả staging đang chạy gì, [infra/tailscale/README.md](infra/tailscale/README.md) là cách vào cluster từ máy local.

## Khác biệt giữa repo và cluster đang chạy

Repo đã đổi tên namespace `platform` thành `infra`, nhưng cluster hiện tại vẫn đang chạy namespace `platform`. Việc đổi tên trên cluster làm khi dựng lại, vì nó kéo theo tạo lại secret bên Google Secret Manager và tạo lại database.

## Để dành sau

- **Prometheus + Grafana**: chưa có gì để xem số liệu.
- **api**: Ingress `api.cine.io.vn` chỉ mở `/api/v1`, cộng Job migration. Xem [apps/README.md](apps/README.md).
- **RabbitMQ**: đã chọn thay BullMQ, chưa dựng.
- **Tailscale trong cluster**: subnet router để vào Argo CD, Postgres, Redis mà không mở thêm port.
- **Backup Postgres** ra object storage: làm trước khi có dữ liệu thật.
- **Middleware Traefik**: rate limit, security header, gzip — nginx cũ bên `cinema` có, ở đây chưa.
- **Luồng ra image mới**: CI của `cinema` build rồi `cinema-release-bot` sửa tag trong repo này.
- **Node thứ hai**: xem phần cuối [bootstrap/README.md](bootstrap/README.md).
