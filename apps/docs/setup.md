# Deploy một app

## Thêm app mới

```text
apps/<app>/base/          deployment.yaml (image không tag), service.yaml
apps/<app>/envs/staging/  kustomization.yaml, deployment-patch.yaml, ingress.yaml
```

Push là xong, ApplicationSet tự sinh Application tên `<app>`.

Gì đổi theo môi trường thì xuống `envs/`: tag, domain, env, số bản chạy. Ingress nằm hẳn trong `envs/` vì gắn với domain.

## Đổi version

```yaml
# envs/staging/kustomization.yaml
images:
  - name: ghcr.io/cine-org/setup-monorepo/web-user
    newTag: v0.2.0
```

Đây cũng là dòng `cinema-release-bot` sẽ sửa tự động sau này.

## Phải nhớ

- Service dùng tên cổng (`targetPort: http`), đổi số cổng không phải sửa Service và Ingress.
- Ingress là đường duy nhất từ Internet; ClusterIP chỉ tới được từ trong cluster.
- `API_ORIGIN` là URL công khai, không phải `*.svc`: code trong trình duyệt không phân giải được tên nội bộ.
- Readiness quyết định pod có nhận request, liveness quyết định pod có bị giết.

## Verify

```bash
kubectl get pods,svc,ingress -n cinema -l app.kubernetes.io/name=<app>
kubectl kustomize apps/<app>/envs/staging      # xem trước khi push
curl -sI https://<host> | head -3
```

`ImagePullBackOff` → xem `infra/ghcr-pull`. Running mà không Ready → probe fail, xem `describe pod`.
