# External Secrets + Google Secret Manager

Mục tiêu: password thật không bao giờ chạm Git, kể cả dưới dạng mã hóa. Chúng nằm ở Google Secret Manager (GSM), cluster chỉ đồng bộ về khi cần.

Chọn GSM vì có tier Always Free lặp lại hàng tháng (6 secret version và 10.000 lượt truy cập), đủ cho quy mô này. Cách khác phổ biến là Sealed Secrets: mã hóa rồi commit vào Git. Ở đây không dùng, vì bản mã hóa vẫn nằm trong lịch sử Git mãi mãi, và mất khóa riêng của controller là mất hết.

## Khái niệm

```text
GSM: infra-postgres = {"username":"cinema","password":"a1b2..."}
  │
  │  ESO đọc, theo chu kỳ refreshInterval
  ▼
Secret K8s infra-postgres (ns infra): username=cinema, password=a1b2...
  │
  ▼
Postgres, Redis, app... đọc Secret như bình thường
```

| Kind | Nghĩa |
| --- | --- |
| `ClusterSecretStore` | kho secret ở đâu, xác thực bằng gì. Cluster-scoped nên mọi namespace dùng chung |
| `SecretStore` | như trên nhưng chỉ trong một namespace |
| `ExternalSecret` | công thức: lấy key nào ở kho, ghi thành Secret K8s tên gì, trong namespace nào |

Git chỉ chứa **công thức**, không chứa giá trị. Secret K8s do ESO sinh ra thuộc sở hữu của `ExternalSecret` (mặc định `creationPolicy: Owner`), nên xóa công thức là Secret mất theo. Argo CD chỉ quản `ExternalSecret`, không thấy giá trị bên trong.

## Việc làm tay, một lần, ngoài Git

### 1. GCP: service account

```text
GCP Console → IAM & Admin → Service Accounts → Create
  Role: Secret Manager Secret Accessor
→ Keys → Add key → JSON → tải về máy
```

### 2. GCP: tạo secret

`Security → Secret Manager → Create secret`. Quy ước đặt tên: `infra-` cho hạ tầng, `cinema-` cho thứ thuộc về app.

| Tên | Value | Dùng ở |
| --- | --- | --- |
| `infra-postgres` | `{"username":"cinema","password":"<hex>"}` | [postgres](../postgres/README.md) |
| `infra-postgres-rw` | `{"username":"cinema_rw","password":"<hex>"}` | postgres |
| `infra-postgres-ro` | `{"username":"cinema_ro","password":"<hex>"}` | postgres |
| `infra-redis` | `{"password":"<hex>"}` | [redis](../redis/README.md) |
| `cinema-ghcr-pull` | `{"username":"<github-user>","token":"<PAT>"}` | [ghcr-pull](../ghcr-pull/README.md) |

Sinh password bằng `openssl rand -hex 24`. Dùng hex để khỏi phải URL-encode khi ghép vào chuỗi kết nối. Value là JSON vì một secret thường cần nhiều field.

### 3. VPS: đưa key của service account vào cluster

Đây là secret duy nhất tạo bằng tay trong cluster: chìa khóa để mở mọi secret còn lại.

```bash
kubectl create secret generic gcpsm-credentials \
  --from-file=secret-access-credentials=<đường-dẫn-file.json> \
  -n infra
```

Namespace `infra` phải có trước, xem [namespaces](../namespaces/README.md). Xóa file JSON khỏi máy sau khi chạy xong.

## File trong thư mục này

`values.yaml` hạ `resources` của chart xuống cho vừa VPS nhỏ.

`base/cluster-secret-store.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-manager
spec:
  provider:
    gcpsm:
      projectID: "<GCP project ID>"
      auth:
        secretRef:
          secretAccessKeySecretRef:
            name: gcpsm-credentials
            key: secret-access-credentials
            namespace: infra
```

Chỉ tham chiếu tên Secret, không chứa giá trị. `namespace` bắt buộc phải ghi, vì `ClusterSecretStore` không thuộc namespace nào nên nó không tự đoán được.

CRD của external-secrets rất lớn, nên Application bắt buộc có `ServerSideApply=true`, nếu không sync sẽ fail vì vượt trần annotation 262144 byte.

## Cách viết một ExternalSecret

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: infra-redis
  namespace: infra
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: infra-redis
  data:
    - secretKey: password          # tên key trong Secret K8s
      remoteRef:
        key: infra-redis           # tên secret bên GSM
        property: password         # field trong JSON; value là chuỗi trần thì bỏ đi
```

- `secretStoreRef.kind` phải ghi rõ `ClusterSecretStore`. Bỏ trống thì ESO hiểu là `SecretStore` namespace-scoped và báo không tìm thấy.
- `target.name` là tên Secret sinh ra; bỏ trống thì lấy `metadata.name`.
- Có cách viết tắt `dataFrom.extract` đổ hết key trong JSON vào Secret. Cố ý không dùng: liệt kê ra thì đọc file là biết Secret có những gì.
- `refreshInterval` là chu kỳ đối chiếu lại GSM. Đổi password bên GSM thì Secret K8s tự cập nhật, nhưng thứ đã dùng password đó thì chưa chắc, ví dụ Postgres chỉ đọc lúc `initdb`.
- `target.template` cho phép nhào nặn ra định dạng khác, ví dụ Secret kiểu `dockerconfigjson`. Xem [ghcr-pull](../ghcr-pull/README.md).

Một cái tên xuất hiện ba lần (`infra-redis`) là ba thứ khác nhau: secret bên GSM, `ExternalSecret`, và Secret K8s. Đặt trùng nhau cho dễ lần theo.

## Verify

```bash
kubectl get clustersecretstore gcp-secret-manager
kubectl get externalsecret -A
```

`ClusterSecretStore` phải `Valid`, mọi `ExternalSecret` phải `SecretSynced`. `Invalid` thường do sai role của service account, sai tên Secret `gcpsm-credentials`, hoặc quên sửa `projectID`.

Xem chi tiết khi hỏng:

```bash
kubectl describe externalsecret <tên> -n <ns>
```

---

Tiếp: [Postgres](../postgres/README.md).
