# GCS

> Google Cloud Storage cho một env: bucket chứa file nằm ngoài VM, hiện dùng cho backup Postgres ([infra/postgres](../../infra/postgres/README.md)). Cluster ghi vào bucket bằng key của một service account riêng, key đi qua GSM ([gsm.md](gsm.md)).

Mỗi env dùng bucket trong project GCP của env đó. Tên bucket là duy nhất trên toàn GCS (mọi khách hàng, không chỉ project này) và không đổi được sau khi tạo, nên tên luôn chứa env: `cinema-<env>-<mục đích>`.

## Bucket mỗi env cần

| Bucket                   | Service account   | Secret GSM              | Dùng cho                                 |
| ------------------------ | ----------------- | ----------------------- | ---------------------------------------- |
| `cinema-<env>-pg-backup` | `postgres-backup` | `infra-postgres-backup` | Postgres: WAL liên tục + base backup đêm |

Thêm bucket mới thì thêm dòng vào bảng này cùng PR dùng nó.

## 1. Bật Cloud Storage API

APIs & Services → Library → **Cloud Storage API** → Enable (project mới thường đã bật sẵn).

## 2. Tạo bucket

Cloud Storage → Buckets → **Create**:

| Mục                                 | Chọn                                                                 |
| ----------------------------------- | -------------------------------------------------------------------- |
| Name                                | `cinema-<env>-pg-backup`                                             |
| Labels                              | `env` = `<env>`                                                      |
| Location type                       | **Region** → `asia-southeast1` (Singapore), cùng region với VM       |
| Storage class                       | **Set a default class** → **Standard** (không dùng Autoclass)        |
| Hierarchical namespace, Rapid Cache | Tắt                                                                  |
| Prevent public access               | **Enforce public access prevention on this bucket** ✅               |
| Access control                      | **Uniform**                                                          |
| Soft delete policy                  | **Set custom retention duration** → `0` (tắt)                        |
| Object versioning, Retention        | Tắt                                                                  |
| Data encryption                     | Google-managed encryption key (mặc định), không đổi encryption rules |

- Region trùng VM: ghi/đọc không tốn phí truyền dữ liệu. Location không đổi được sau khi tạo.
- Standard thay vì Nearline/Coldline: các class rẻ hơn tính tối thiểu 30/90 ngày lưu và tính phí đọc, trong khi backup ở đây bị xoá sau 14 ngày và restore phải đọc lại. Autoclass cũng chuyển dần sang Nearline nên không dùng.
- Soft delete `0`: thời gian giữ backup do Postgres tự quản (`retentionPolicy` trong [infra/postgres](../../infra/postgres/README.md)); soft delete mặc định 7 ngày chỉ giữ thêm bản đã xoá và tính phí cho chúng.

### Lifecycle (lưới an toàn)

Bucket → Lifecycle → **Add a rule**: Action **Delete object**, Condition **Age = 30 days**.

Postgres đã tự xoá backup quá 14 ngày. Rule này chỉ dọn phần sót lại nếu việc tự xoá hỏng, nên để dài hơn hẳn 14 ngày: xoá sớm hơn là mất base backup đang cần để restore.

## 3. Service account

IAM & Admin → Service Accounts → **Create service account**: Name `postgres-backup`, **không** gán role ở bước này (role cấp cho cả project).

Cấp quyền chỉ trên bucket: Cloud Storage → Buckets → `cinema-<env>-pg-backup` → Permissions → **Grant access**:

| Mục           | Giá trị                                             |
| ------------- | --------------------------------------------------- |
| New principal | `postgres-backup@<project>.iam.gserviceaccount.com` |
| Role          | **Storage Object Admin** (đọc, ghi, xoá object)     |

Không dùng role ở cấp project: key bị lộ thì chỉ ảnh hưởng đúng bucket này.

## 4. Key

Service account → Keys → Add key → Create new key → JSON. File key tải về đặt tên `infra-postgres-backup.json`, đưa lên GSM thành secret `infra-postgres-backup` ([gsm.md](gsm.md) mục 3).

Đổi key: tạo key mới → New version trên GSM → force-sync ExternalSecret `postgres-backup` (ns `infra`) → xoá key cũ trong service account.

## Chi phí

Standard ở `asia-southeast1` tính theo GB lưu mỗi tháng, cộng phí mỗi lần ghi/đọc. Database nhỏ với 14 ngày WAL + base backup chỉ vài GB: vài xu tới vài chục xu mỗi tháng.

## Verify

```bash
gcloud storage buckets describe gs://cinema-<env>-pg-backup --format="value(location,iamConfiguration.publicAccessPrevention)"
gcloud storage ls gs://cinema-<env>-pg-backup/postgres/      # có thư mục sau lần backup đầu
```
