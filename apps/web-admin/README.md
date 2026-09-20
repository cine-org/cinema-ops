# web-admin

Web cho quản trị. Domain `https://admin.cine.io.vn`.

| | |
| --- | --- |
| Image | `ghcr.io/cine-org/setup-monorepo/web-admin`, tag đặt ở `envs/staging/kustomization.yaml` |
| Port | 80, đặt tên `http` |
| Health | `GET /healthz` cho cả readiness và liveness |
| Namespace | `cinema` |
| Secret kéo image | `ghcr-pull`, xem [infra/ghcr-pull](../../infra/ghcr-pull/README.md) |
| Chứng chỉ | `admin-cine-io-vn-tls`, cert-manager tự xin từ `letsencrypt-prod` |

## File

```text
base/deployment.yaml     image không tag, probe, resources, imagePullSecrets
base/service.yaml        ClusterIP 80 → cổng http của pod
envs/staging/kustomization.yaml    newTag + patch
envs/staging/deployment-patch.yaml API_ORIGIN, API_PREFIX
envs/staging/ingress.yaml          host admin.cine.io.vn + TLS
```

## Vài chỗ đáng chú ý

**Probe.** Readiness quyết định pod có được nhận request hay không; liveness quyết định pod có bị giết và dựng lại hay không. Cả hai gọi `/healthz`. Readiness 5 giây một lần; liveness chờ 10 giây rồi 10 giây một lần, thưa hơn để pod khởi động chậm không bị giết oan.

**Service dùng tên cổng, không dùng số.** `targetPort: http` trỏ tới cổng tên `http` của container. Đổi số cổng trong Deployment thì Service và Ingress không phải sửa theo.

**Ingress là đường duy nhất từ Internet.** Service kiểu ClusterIP chỉ tới được từ trong cluster. Annotation `cert-manager.io/cluster-issuer` khiến cert-manager tự tạo `Certificate` và ghi vào Secret `admin-cine-io-vn-tls`; không phải viết `Certificate` bằng tay.

**`API_ORIGIN` là URL công khai của api**, không phải tên nội bộ trong cluster. Code chạy trong trình duyệt gọi api, mà trình duyệt không phân giải được `api.cinema.svc`. Xem phần "Đường gọi api" trong [apps/README.md](../README.md).

## Đổi phiên bản

```yaml
# envs/staging/kustomization.yaml
images:
  - name: ghcr.io/cine-org/setup-monorepo/web-admin
    newTag: v0.2.0
```

Push là xong. Xem lại trước khi push:

```bash
kubectl kustomize apps/web-admin/envs/staging
```

## Verify

```bash
kubectl get pods,svc,ingress -n cinema -l app.kubernetes.io/name=web-admin
kubectl get certificate admin-cine-io-vn-tls -n cinema
curl -sI https://admin.cine.io.vn | head -3
curl -sI http://admin.cine.io.vn | head -3
```

Mong đợi pod Running và Ready, `Certificate` `READY=True`, HTTPS trả 200, HTTP trả 301 hoặc 308.

Pod kẹt ở `ImagePullBackOff` thì xem [infra/ghcr-pull](../../infra/ghcr-pull/README.md). Pod Running mà không Ready thì probe đang fail:

```bash
kubectl describe pod -n cinema -l app.kubernetes.io/name=web-admin | grep -A10 Events
```

## Tăng số bản chạy

Sửa `replicas` trong `base/deployment.yaml`, hoặc thêm patch ở `envs/staging` nếu chỉ muốn đổi riêng staging. Pod đang chạy không bị đụng tới, Service tự thêm pod mới vào EndpointSlice và chia request.

Trên một node thì nhiều bản chỉ chống pod chết, không chống VPS chết. Có node thứ hai thì nên thêm `podAntiAffinity` và PodDisruptionBudget.
