# External Secrets + GSM

> Chọn GSM vì tier Always Free lặp hàng tháng. Prefix tên: `infra-` cho hạ tầng, `cinema-` cho app.

## 1. GCP: service account

```text
IAM & Admin → Service Accounts → Create
  Role: Secret Manager Secret Accessor
→ Keys → Add key → JSON
```

## 2. GCP: tạo secret

`Security → Secret Manager → Create secret`. Password: `openssl rand -hex 24` (hex để khỏi URL-encode).

| Tên | Value |
| --- | --- |
| `infra-postgres` | `{"username":"cinema","password":"<hex>"}` |
| `infra-postgres-rw` | `{"username":"cinema_rw","password":"<hex>"}` |
| `infra-postgres-ro` | `{"username":"cinema_ro","password":"<hex>"}` |
| `infra-redis` | `{"password":"<hex>"}` |
| `cinema-ghcr-pull` | `{"username":"<github-user>","token":"<PAT>"}` |

## 3. VPS: key vào cluster

Secret duy nhất tạo tay — chìa khóa mở mọi secret còn lại.

```bash
kubectl create secret generic gcpsm-credentials \
  --from-file=secret-access-credentials=<file.json> \
  -n infra
```

Xóa file JSON khỏi máy sau đó.

## Mẫu ExternalSecret

```yaml
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore     # bỏ trống → ESO hiểu là SecretStore, không thấy
  target:
    name: infra-redis            # tên Secret K8s sinh ra
  data:
    - secretKey: password        # key trong Secret K8s
      remoteRef:
        key: infra-redis         # tên secret bên GSM
        property: password       # field trong JSON
```

- Secret sinh ra thuộc sở hữu `ExternalSecret` — xóa công thức là Secret mất theo.
- `target.template` để nhào ra định dạng khác, ví dụ `dockerconfigjson` (xem `infra/ghcr-pull`).
- Không dùng `dataFrom.extract`: liệt kê ra thì đọc file biết ngay Secret có gì.
- CRD rất lớn → Application bắt buộc `ServerSideApply=true`.

## Verify

```bash
kubectl get clustersecretstore        # Valid
kubectl get externalsecret -A         # SecretSynced
kubectl describe externalsecret <tên> -n <ns>
```

`Invalid` thường do sai role service account, sai tên `gcpsm-credentials`, hoặc quên sửa `projectID`.
