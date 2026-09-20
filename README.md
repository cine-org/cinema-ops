# cinema-ops

GitOps cho cluster của `cinema`. Argo CD đọc repo này, cluster tự khớp theo.

```text
bootstrap/          VPS, k3s, Argo CD — chạy tay 1 lần
clusters/staging/   staging chạy gì: Application + ApplicationSet
infra/<feat>/       hạ tầng: values.yaml + base/ + envs/<env>/
apps/<app>/         app: base/ + envs/<env>/
```

Mỗi thư mục có `README.md` (nó là gì) và `docs/` (làm thế nào).

## Quy ước

- Argo CD luôn trỏ vào `envs/<env>`, không trỏ vào `base/`.
- Thư mục có `base/` thì có 1 Application cùng tên trong `clusters/staging/`.
- Application nào cũng có `ServerSideApply=true` + `retry`.
- CR của operator mang `sync-wave: "1"` (khai trong `base/kustomization.yaml`).

## Dựng lại từ đầu

1. [bootstrap/docs/vps.md](bootstrap/docs/vps.md)
2. [bootstrap/docs/k3s.md](bootstrap/docs/k3s.md)
3. [bootstrap/docs/argocd.md](bootstrap/docs/argocd.md)
4. [infra/namespaces](infra/namespaces/docs/setup.md)
5. [infra/external-secrets](infra/external-secrets/docs/setup.md)
6. [infra/postgres](infra/postgres/docs/setup.md)
7. [infra/redis](infra/redis/docs/setup.md)
8. [infra/cert-manager](infra/cert-manager/docs/setup.md)
9. [infra/traefik](infra/traefik/docs/setup.md)
10. [infra/ghcr-pull](infra/ghcr-pull/docs/setup.md)
11. [apps](apps/docs/setup.md)

## Lưu ý

Repo ghi namespace `infra`, cluster đang chạy còn tên cũ `platform`. Đổi khi dựng lại.
