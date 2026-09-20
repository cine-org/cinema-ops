# apps

App của repo `cinema`, chạy ở ns `cinema`. ApplicationSet trong `clusters/staging/apps.yaml` tự sinh Application cho mỗi thư mục.

| App | Domain | Trạng thái |
| --- | --- | --- |
| [web-user](web-user) | `cine.io.vn` | đang chạy |
| [web-admin](web-admin) | `admin.cine.io.vn` | đang chạy |
| api | `api.cine.io.vn` | chưa dựng |
| worker, scheduler, integration | — | chưa dựng |

```text
<app>/base/            deployment (image không tag), service
<app>/envs/staging/    newTag, patch env, ingress
```

- [docs/setup.md](docs/setup.md) — thêm app, đổi version
- [docs/contract.md](docs/contract.md) — hợp đồng với repo `cinema`
