# clusters/staging

Staging chạy những gì. Nội dung từng thứ ở `infra/<feat>/` và `apps/<app>/`.

```text
root-staging → clusters/staging/
                 ├── infra/*.yaml   7 Application
                 └── apps.yaml      ApplicationSet → 1 Application mỗi app
```

| Application | Chart | Manifest |
| --- | --- | --- |
| `namespaces` | — | `infra/namespaces/` |
| `external-secrets` | external-secrets | `infra/external-secrets/` |
| `postgres` | cloudnative-pg | `infra/postgres/` |
| `redis` | redis-operator | `infra/redis/` |
| `cert-manager` | cert-manager | `infra/cert-manager/` |
| `traefik` | — (k3s có sẵn) | `infra/traefik/` |
| `ghcr-pull` | — | `infra/ghcr-pull/` |

`helm.releaseName` ghim tên release cũ (`cnpg-operator`, `redis-operator`) vì Argo CD mặc định lấy tên Application làm tên release.

ApplicationSet quét `apps/*/envs/staging`, tên Application lấy từ `{{ index .path.segments 1 }}`. Thêm app = tạo thư mục. Không dùng ApplicationSet cho `infra/` vì mỗi chart một kiểu.

- [docs/cheatsheet.md](docs/cheatsheet.md)
