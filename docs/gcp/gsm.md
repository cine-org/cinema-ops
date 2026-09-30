# GSM

> Google Secret Manager cho một env: nơi giữ giá trị secret. Cluster đọc qua External Secrets ([infra/external-secrets](../../infra/external-secrets/README.md)). Git chỉ chứa công thức, không chứa giá trị.

Mỗi env dùng GSM của project GCP riêng (staging: `cinema-stag`). Tên secret giống nhau ở mọi env.

## 1. Bật Secret Manager API

APIs & Services → Library → **Secret Manager API** → Enable.

## 2. Service account cho ESO

IAM & Admin → Service Accounts → **Create service account**:

| Mục  | Giá trị                                      |
| ---- | -------------------------------------------- |
| Name | `external-secrets`                           |
| Role | **Secret Manager Secret Accessor** (chỉ đọc) |

Mở service account → Keys → Add key → Create new key → JSON. Lưu thành file `gcpsm-credentials.json` ([bootstrap](../../bootstrap/README.md) mục Chuẩn bị). Key này được tạo tay trong cluster ([bootstrap](../../bootstrap/README.md), mục 3.3).

Không dùng service account mặc định của VM: ESO chỉ cần đọc secret, key riêng thì thu hồi riêng được.

## 3. Tạo secret

Security → Secret Manager → **Create secret**: Name = tên secret, Secret value = upload file `<tên>`, Replication = Automatic.

File local giữ đúng tên secret để khi dựng lại chỉ việc upload lại.

Password tự sinh là chuỗi hex, không có dấu xuống dòng ở cuối (dấu xuống dòng sẽ thành một phần của password):

```bash
openssl rand -hex 24 | tr -d '\n' > <tên>
```

| Tên                       | Giá trị                                                                  | Dùng cho                        |
| ------------------------- | ------------------------------------------------------------------------ | ------------------------------- |
| `infra-argocd-github-app` | file `.pem` của GitHub App `argocd-cinema-ops-reader`, key riêng của env | Argo CD đọc repo, commit status |
| `infra-argocd-webhook`    | chuỗi ngẫu nhiên, trùng Secret của webhook GitHub trên `cinema-ops`      | Argo CD xác thực webhook        |
| `infra-postgres`          | password role `cinema` (owner)                                           | Postgres, chạy migration        |
| `infra-postgres-rw`       | password role `cinema_rw`                                                | Postgres, api lúc chạy          |
| `infra-postgres-ro`       | password role `cinema_ro`                                                | Postgres, chỉ đọc               |
| `cinema-ghcr-pull`        | `{"username":"<github-user>","token":"<PAT classic read:packages>"}`     | cluster kéo image từ `ghcr.io`  |

Thêm secret mới thì thêm dòng vào bảng này cùng PR dùng nó. Prefix: `infra-` cho hạ tầng, `cinema-` cho app.

## Đổi giá trị

Secret → **New version** → dán giá trị mới. ESO lấy bản `latest` ở lần refresh kế tiếp (`refreshInterval`), hoặc ép ngay:

```bash
kubectl annotate externalsecret <tên> -n <ns> force-sync=$(date +%s) --overwrite
```

App chạy ổn với giá trị mới thì **Destroy** version cũ (không Disable: version bị disable vẫn tính phí, destroy thì không, nhưng không khôi phục được).

## Chi phí

Always Free mỗi tháng: 6 secret version đang active và 10.000 lần đọc. ESO đọc mỗi ExternalSecret 1 lần/`refreshInterval` (1h ≈ 720 lần/tháng), nên giữ `refreshInterval: 1h` và destroy version cũ để không vượt free.

## Verify

```bash
kubectl get clustersecretstore        # gcp-secret-manager Valid
kubectl get externalsecret -A         # SecretSynced
```
