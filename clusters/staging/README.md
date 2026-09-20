# Staging

Thư mục này trả lời một câu: **staging đang chạy những gì.** Nội dung của từng thứ nằm ở `infra/<feat>/` và `apps/<app>/`, ở đây chỉ là danh sách và cách nối dây.

```text
root-staging  (apply tay, ở bootstrap/argocd/staging/root-application.yaml)
  └── clusters/staging/            ← recurse: true
        ├── infra/*.yaml           → 7 Application
        └── apps.yaml              → ApplicationSet → Application cho mỗi app
```

## Hạ tầng

Mỗi file là một Application, tên file trùng tên Application và trùng tên thư mục trong `infra/`.

| Application | Chart | Manifest | Namespace |
| --- | --- | --- | --- |
| `namespaces` | — | `infra/namespaces/` | tạo `cinema`, `infra` |
| `external-secrets` | external-secrets | `infra/external-secrets/` | `infra` |
| `postgres` | cloudnative-pg | `infra/postgres/` | operator ở `cnpg-system`, database ở `infra` |
| `redis` | redis-operator | `infra/redis/` | operator ở `redis-operator`, Redis ở `infra` |
| `cert-manager` | cert-manager | `infra/cert-manager/` | `cert-manager` |
| `traefik` | — (k3s có sẵn) | `infra/traefik/` | `kube-system` |
| `ghcr-pull` | — | `infra/ghcr-pull/` | `cinema` |

Feat nào vừa có chart vừa có manifest thì Application khai hai source: chart, và thư mục `envs/staging` của feat đó. Xem phần "Quy ước" trong [README gốc](../../README.md).

Ba tên Helm release bị ghim cứng bằng `helm.releaseName`: `cnpg-operator` và `redis-operator`. Lý do: Argo CD mặc định lấy tên Application làm tên release, mà hai Application này đã đổi tên thành `postgres` và `redis`. Không ghim thì chart sinh ra một bộ tài nguyên mang tên mới, tức có hai operator cùng chạy.

## Apps

`apps.yaml` là một **ApplicationSet**: Argo CD quét các thư mục khớp `apps/*/envs/staging` rồi tự sinh một Application cho mỗi thư mục, tên lấy theo tên app.

```yaml
generators:
  - git:
      repoURL: https://github.com/cine-org/cinema-ops.git
      revision: main
      directories:
        - path: apps/*/envs/staging
template:
  metadata:
    name: '{{ index .path.segments 1 }}'   # apps / <app> / envs / staging
```

Thêm app mới thì chỉ cần tạo thư mục và push, không phải viết Application. Xóa thư mục thì Application biến mất theo.

Không dùng ApplicationSet cho `infra/` vì mỗi chart một kiểu: repo khác nhau, version khác nhau, namespace khác nhau, có cái không có chart. Nhét hết khác biệt đó vào một generator sẽ rối hơn là viết bảy file.

## Thêm một môi trường

Tạo `clusters/production/` với cùng bộ file, sửa `path` trỏ sang `envs/production`, rồi tạo `envs/production/` trong từng feat và app. `base/` dùng lại, không chép.

Cần một root application nữa trong `bootstrap/argocd/production/` và một cluster khác để trỏ tới.

## Verify

```bash
kubectl get app -n argocd
kubectl get appset -n argocd
```

Mong đợi 10 Application `Synced/Healthy`: 7 hạ tầng, 2 app, và `root-staging`.
