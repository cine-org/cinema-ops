# external-secrets

External Secrets Operator (ESO) chép secret từ Google Secret Manager (GSM) vào cluster. Git chỉ chứa khai báo `ExternalSecret` (lấy secret nào, đặt vào đâu), không chứa giá trị.

Cách tạo GSM, service account và secret: [docs/gcp/gsm.md](../../docs/gcp/gsm.md).

```text
GSM ─▶ ESO ─▶ Secret K8s ─▶ pod / Argo CD
       └─ đăng nhập GSM bằng key trong secret gcpsm-credentials (ns infra)
```

- `base/cluster-secret-store.yaml`: `ClusterSecretStore gcp-secret-manager`, chỗ ESO biết GSM nằm ở project nào và dùng key nào. Mọi namespace dùng chung.
- `envs/<env>/kustomization.yaml`: điền `projectID` GCP của env.

## Mẫu ExternalSecret

```yaml
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore # bắt buộc; bỏ trống thì ESO tìm SecretStore và không thấy
  target:
    name: infra-redis # tên Secret K8s được tạo ra
  data:
    - secretKey: password # key trong Secret K8s
      remoteRef:
        key: infra-redis # tên secret trên GSM
        property: password # field trong JSON; bỏ dòng này nếu secret là chuỗi thường
```

## Phải nhớ

- Xoá `ExternalSecret` thì Secret K8s nó tạo ra cũng bị xoá.
- Muốn thêm key vào một Secret đã có sẵn (không để ESO tạo mới) thì dùng `creationPolicy: Merge`. Ví dụ: `cinema-ops-repo` của Argo CD.
- Cần định dạng khác thì dùng `target.template`. Ví dụ: `dockerconfigjson` ở `infra/ghcr-pull`.
- Liệt kê từng key trong `data`, không dùng `dataFrom.extract`, để đọc file là biết Secret có những gì.
- `ExternalSecret` nằm ngoài app `external-secrets` phải có annotation `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`. Lý do: lúc dựng mới, chart ESO chưa cài xong thì Kubernetes chưa biết kiểu `ExternalSecret`.
- `ClusterSecretStore` có `sync-wave: "1"` để chờ chart cài xong rồi mới tạo.

## Verify

```bash
kubectl get pods -n infra -l app.kubernetes.io/instance=external-secrets   # Running
kubectl get clustersecretstore                                             # Valid
kubectl get externalsecret -A                                              # SecretSynced
```

`ClusterSecretStore` báo `InvalidProviderConfig` hoặc `Invalid` thì kiểm tra lần lượt:

1. Secret `gcpsm-credentials` có trong ns `infra` chưa.
2. Service account có role Secret Manager Secret Accessor chưa.
3. `projectID` có đúng không.
4. Secret Manager API đã bật chưa.
