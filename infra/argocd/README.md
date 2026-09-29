# argocd

Argo CD tự quản lý bằng GitOps. Root app (`bootstrap/root/<env>.yaml`, apply tay) cài chart `argo-cd` với `values.yaml` và thư mục `envs/<env>`:

- `base/namespaces.yaml`: namespace `cinema`, `infra`, tạo trước mọi thứ và không bao giờ prune;
- `base/infra.yaml`: ApplicationSet `infra`, mỗi `infra/<feat>/envs/<env>` thành 1 Application (trừ `infra/argocd`);
- `base/apps.yaml`: ApplicationSet `apps`, mỗi `apps/<app>/envs/<env>` thành 1 Application ở ns `cinema`.

```text
bootstrap/root/<env>.yaml ─▶ chart argo-cd + infra/argocd/envs/<env>
                                  ├─ ApplicationSet infra ─▶ infra/<feat>/envs/<env>   (chart khai ở infra/<feat>/app.yaml)
                                  └─ ApplicationSet apps  ─▶ apps/<app>/envs/<env>
```

`infra/<feat>/app.yaml` khai `namespace`, và `chart` (`repo`, `name`, `version`, `release`) nếu cài bằng Helm. Values của chart: `infra/<feat>/values.yaml` + `infra/<feat>/envs/<env>/values.yaml`.

## Phải nhớ

- Có thư mục `envs/<env>` = bật ở env đó. Không viết Application tay.
- Tên env chỉ nằm ở `envs/<env>/kustomization.yaml` (patch path của 2 ApplicationSet) và `bootstrap/root/<env>.yaml`.
- `syncPolicy` (auto sync, prune, selfHeal, retry, `ServerSideApply`) khai 1 lần trong 2 ApplicationSet.
- Đổi cấu hình Argo CD = sửa `values.yaml` rồi push. Đổi version chart = sửa `targetRevision` trong root rồi apply lại root.
- Credential đọc repo: secret `cinema-ops-repo` tạo tay lúc bootstrap (GitHub App `argocd-cinema-ops-reader`); sẽ chuyển sang External Secrets.
- Chưa có: Ingress + webhook (Argo CD poll GitHub mỗi 3 phút), commit status. Làm cùng External Secrets và TLS.

## Verify

```bash
kubectl kustomize infra/argocd/envs/<env>      # xem trước khi push
kubectl get app,applicationset -n argocd       # Synced/Healthy
```

Application kẹt `Unknown`/`ComparisonError`: `kubectl describe app <tên> -n argocd`, thường do path hoặc `app.yaml` sai.
