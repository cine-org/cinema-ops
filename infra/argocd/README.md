# argocd

Argo CD quản lý chính nó bằng GitOps: sau khi apply tay root app (`bootstrap/root/<env>.yaml`) một lần, mọi thay đổi của Argo CD đi qua `git push`.

Root app cài 2 thứ:

1. Chart `argo-cd`, với cấu hình ở `values.yaml`.
2. Thư mục `envs/<env>`, gồm các file trong `base/`:

| File                    | Nội dung                                                                   |
| ----------------------- | -------------------------------------------------------------------------- |
| `namespaces.yaml`       | Namespace `cinema` và `infra`. Tạo trước mọi thứ, không bao giờ bị xoá.    |
| `infra.yaml`            | ApplicationSet `infra`: mỗi thư mục `infra/<feat>/envs/<env>` thành 1 app. |
| `apps.yaml`             | ApplicationSet `apps`: mỗi thư mục `apps/<app>/envs/<env>` thành 1 app.    |
| `external-secrets.yaml` | Lấy key GitHub App từ GSM cho credential đọc repo.                         |

```text
bootstrap/root/<env>.yaml ─▶ chart argo-cd + infra/argocd/envs/<env>
                                  ├─ ApplicationSet infra ─▶ infra/<feat>/envs/<env>
                                  └─ ApplicationSet apps  ─▶ apps/<app>/envs/<env>
```

## Thêm một thành phần hạ tầng

Tạo thư mục `infra/<feat>/` với:

- `app.yaml`: khai `namespace`. Nếu cài bằng Helm thì khai thêm `chart` (`repo`, `name`, `version`, `release`).
- `values.yaml`: values chung của chart. Values riêng từng env đặt ở `envs/<env>/values.yaml`.
- `envs/<env>/`: có thư mục này thì thành phần được bật ở env đó.

Không viết Application bằng tay: ApplicationSet tự sinh.

## Phải nhớ

- Tên env chỉ xuất hiện ở 2 chỗ: `envs/<env>/kustomization.yaml` và `bootstrap/root/<env>.yaml`.
- `syncPolicy` (auto sync, prune, selfHeal, retry, `ServerSideApply`) chỉ khai trong 2 ApplicationSet.
- Đổi cấu hình Argo CD: sửa `values.yaml` rồi push. Đổi version chart: sửa `targetRevision` trong root app rồi apply lại root app.
- Credential đọc repo là secret `cinema-ops-repo`, tạo tay lúc bootstrap. Sau đó ExternalSecret trong `external-secrets.yaml` giữ key trong secret này khớp với GSM `infra-argocd-github-app`. Nó chỉ ghi đè key, không đụng các field khác (`creationPolicy: Merge`).
- Chưa có Ingress và webhook nên Argo CD tự kiểm tra GitHub 3 phút một lần. Commit status cũng chưa có. Hai việc này làm cùng TLS.

## Verify

```bash
kubectl kustomize infra/argocd/envs/<env>      # xem trước khi push
kubectl get app,applicationset -n argocd       # Synced/Healthy
```

App kẹt ở `Unknown` hoặc `ComparisonError`: chạy `kubectl describe app <tên> -n argocd`. Nguyên nhân thường là sai path hoặc sai `app.yaml`.
