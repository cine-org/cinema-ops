# Deploy một app

## Thêm app mới

```text
apps/<app>/base/         deployment.yaml, service.yaml, kustomization.yaml
apps/<app>/envs/staging/ kustomization.yaml, deployment-patch.yaml, ingress.yaml
```

Push là xong: ApplicationSet tự sinh Application tên `<app>`.

Chia base/envs theo nguyên tắc: gì đổi theo môi trường thì xuống `envs/` — tag image, domain, env, số bản chạy. Ingress nằm hẳn trong `envs/` vì gắn với domain.

## Đổi version

```yaml
# envs/staging/kustomization.yaml
images:
  - name: ghcr.io/cine-org/setup-monorepo/web-user
    newTag: v0.2.0
```

```bash
kubectl kustomize apps/web-user/envs/staging      # xem trước
```

Đây cũng là dòng `cinema-release-bot` sẽ sửa tự động sau này.

## Điểm phải nhớ

- Service dùng tên cổng (`targetPort: http`), không dùng số — đổi cổng trong Deployment thì Service và Ingress không phải sửa.
- Ingress là đường duy nhất từ Internet; Service ClusterIP chỉ tới được từ trong cluster.
- `API_ORIGIN` là URL công khai của api, không phải `*.svc`: code chạy trong trình duyệt không phân giải được tên nội bộ.
- Readiness quyết định pod có nhận request; liveness quyết định pod có bị giết. Cả hai gọi `/healthz`.

## Verify

```bash
kubectl get pods,svc,ingress -n cinema -l app.kubernetes.io/name=<app>
kubectl get certificate -n cinema
curl -sI https://<host> | head -3
```

Pod `ImagePullBackOff` → xem `infra/ghcr-pull`. Running mà không Ready → probe fail, xem `kubectl describe pod`.
