# argocd

Argo CD quản lý chính nó bằng GitOps: sau khi apply tay root app (`bootstrap/root/<env>.yaml`) một lần, mọi thay đổi của Argo CD đi qua `git push`.

Root app cài 2 thứ:

1. Chart `argo-cd`, với cấu hình ở `values.yaml`.
2. Thư mục `envs/<env>`: các file trong `base/`, cộng Ingress webhook riêng của env (`envs/<env>/ingress.yaml`).

| File                    | Nội dung                                                                   |
| ----------------------- | -------------------------------------------------------------------------- |
| `namespaces.yaml`       | Namespace `cinema` và `infra`. Tạo trước mọi thứ, không bao giờ bị xoá.    |
| `infra.yaml`            | ApplicationSet `infra`: mỗi thư mục `infra/<feat>/envs/<env>` thành 1 app. |
| `apps.yaml`             | ApplicationSet `apps`: mỗi thư mục `apps/<app>/envs/<env>` thành 1 app.    |
| `external-secrets.yaml` | Lấy từ GSM: key GitHub App (đọc repo, commit status), secret webhook.      |

```text
bootstrap/root/<env>.yaml ─▶ chart argo-cd + infra/argocd/envs/<env>
                                  ├─ ApplicationSet infra ─▶ infra/<feat>/envs/<env>
                                  └─ ApplicationSet apps  ─▶ apps/<app>/envs/<env>

push cinema-ops ─webhook─▶ Argo CD refresh + sync ─notifications─▶ commit status argocd/<env>/<app>
```

## Webhook

GitHub gọi `https://argocd.<domain>/api/webhook` mỗi lần push, Argo CD refresh ngay thay vì chờ lượt kiểm tra 3 phút. Ingress chỉ mở đúng path này; UI vẫn vào qua SSH tunnel ([bootstrap](../../bootstrap/README.md), mục UI).

Webhook sai chữ ký bị bỏ qua. Đúng chữ ký thì cũng chỉ làm Argo CD refresh, không đổi được gì trong cluster.

Khai một lần mỗi env, sau khi Ingress có chứng chỉ: GitHub → `cine-org/cinema-ops` → Settings → Webhooks → Add webhook:

| Mục          | Giá trị                                |
| ------------ | -------------------------------------- |
| Payload URL  | `https://argocd.<domain>/api/webhook`  |
| Content type | `application/json`                     |
| Secret       | giá trị của GSM `infra-argocd-webhook` |
| Events       | Just the push event                    |

## Commit status

Sau mỗi lần sync, Argo CD gắn status `argocd/<env>/<app>` (pending → success hoặc failure) vào commit **cinema-ops** vừa sync, bằng GitHub App `argocd-cinema-ops-reader`. Trigger và template khai trong `values.yaml`, mục `notifications`.

Chỉ app có label `commit-status: "true"` mới báo, tức các app của ApplicationSet `apps`. App hạ tầng không báo.

## Thêm một thành phần hạ tầng

Tạo thư mục `infra/<feat>/` với:

- `app.yaml`: khai `namespace`. Nếu cài bằng Helm thì khai thêm `chart` (`repo`, `name`, `version`, `release`).
- `values.yaml`: values chung của chart. Values riêng từng env đặt ở `envs/<env>/values.yaml`.
- `envs/<env>/`: có thư mục này thì thành phần được bật ở env đó.

Không viết Application bằng tay: ApplicationSet tự sinh.

## Phải nhớ

- Tên env và domain chỉ xuất hiện trong `envs/<env>/` và `bootstrap/root/<env>.yaml`.
- `syncPolicy` (auto sync, prune, selfHeal, retry, `ServerSideApply`) chỉ khai trong 2 ApplicationSet.
- Đổi cấu hình Argo CD: sửa `values.yaml` rồi push. Đổi version chart: sửa `targetRevision` trong root app rồi apply lại root app.
- Credential đọc repo là secret `cinema-ops-repo`, tạo tay lúc bootstrap. Sau đó ExternalSecret trong `external-secrets.yaml` giữ key trong secret này khớp với GSM `infra-argocd-github-app`. Nó chỉ ghi đè key, không đụng các field khác (`creationPolicy: Merge`).
- `argocd-secret` do chart tạo; ExternalSecret `argocd-webhook` chỉ thêm key `webhook.github.secret` (`creationPolicy: Merge`).
- `argocd-notifications-secret` do ExternalSecret tạo, nên chart tắt tạo secret này (`notifications.secret.create: false`).

## Verify

```bash
kubectl kustomize infra/argocd/envs/<env>      # xem trước khi push
kubectl get app,applicationset -n argocd       # Synced/Healthy
kubectl get externalsecret -n argocd           # SecretSynced
kubectl logs -n argocd deploy/argocd-notifications-controller --tail=20
gh api repos/cine-org/cinema-ops/commits/<sha>/statuses --jq '.[] | "\(.context) \(.state)"'
```

Webhook: GitHub → Settings → Webhooks → Recent Deliveries, response `200`.

App kẹt ở `Unknown` hoặc `ComparisonError`: chạy `kubectl describe app <tên> -n argocd`. Nguyên nhân thường là sai path hoặc sai `app.yaml`.
