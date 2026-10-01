# postgres

Postgres chạy bằng operator CloudNativePG (CNPG). Operator là chương trình theo dõi `Cluster` trong git và tự dựng Postgres theo đó: tạo pod, ổ đĩa, Service, role.

- Operator: ns `cnpg-system` (chart `cloudnative-pg`).
- Database: `Cluster postgres` ở ns `infra`, 1 instance, database `cinema`, ổ 5Gi.
- Backup: plugin [barman-cloud](../barman-cloud/README.md), lên bucket `cinema-<env>-pg-backup` ([docs/gcp/gcs.md](../../docs/gcp/gcs.md)).

## Role

| Role        | Quyền                                   | Dùng cho       | Secret K8s (GSM cùng tên) |
| ----------- | --------------------------------------- | -------------- | ------------------------- |
| `cinema`    | chủ database, được tạo/sửa bảng         | chạy migration | `infra-postgres`          |
| `cinema_rw` | `pg_read_all_data`, `pg_write_all_data` | api lúc chạy   | `infra-postgres-rw`       |
| `cinema_ro` | `pg_read_all_data`                      | đường chỉ đọc  | `infra-postgres-ro`       |

GSM chỉ giữ password (chuỗi trơn). Username bằng đúng tên role, không phải bí mật, nên nằm trong `base/external-secrets.yaml`.

`pg_read_all_data` và `pg_write_all_data` là role có sẵn của Postgres, áp quyền cho mọi bảng kể cả bảng migration tạo sau này. Nhờ vậy không cần chạy `GRANT` sau mỗi migration. Hai role này không gồm `TRUNCATE` và không cho tạo/sửa bảng.

## Kết nối

```text
postgresql://cinema_rw:<password>@postgres-rw.infra.svc:5432/cinema
```

| Service       | Đi tới                                   |
| ------------- | ---------------------------------------- |
| `postgres-rw` | primary, đọc và ghi                      |
| `postgres-r`  | mọi instance, chỉ đọc                    |
| `postgres-ro` | chỉ replica; khi còn 1 instance thì rỗng |

Khi còn 1 instance, đường chỉ đọc trỏ vào `postgres-r`.

## Phải nhớ

- `bootstrap.initdb` chỉ chạy **một lần** lúc cluster còn rỗng. Sửa sau đó không tạo lại database, và không đổi được password của `cinema`: đổi password owner phải làm tay bằng `ALTER ROLE`.
- Password của `cinema_rw`, `cinema_ro` thì CNPG tự cập nhật theo Secret (`managed.roles`), nhưng chỉ ở lần reconcile kế tiếp. Ép ngay: `kubectl rollout restart deployment cnpg-operator-cloudnative-pg -n cnpg-system`.
- Trong `managed.roles`, `inherit: true` và `connectionLimit: -1` là giá trị mặc định nhưng **vẫn phải khai**: webhook của CNPG tự điền chúng vào, thiếu trong git thì app OutOfSync mãi.
- Secret của role phải có key `username` đúng bằng tên role. Sai thì CNPG bỏ qua role đó mà `Cluster` vẫn báo healthy.
- Không khai `storageClass` nên dùng `local-path` của k3s: dữ liệu nằm trên đĩa VPS, PVC không thu nhỏ được.
- Không đặt `limits.cpu`: vượt CPU chỉ bị chậm lại, RAM mới cần chặn cứng.

## Verify

```bash
kubectl get cluster -n infra                 # Cluster in healthy state
kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'; echo
```

Phân quyền phải thử bằng lệnh thật, `\du` không đủ:

```bash
PW=$(kubectl get secret infra-postgres-rw -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra postgres-1 -c postgres -- env PGPASSWORD="$PW" \
  psql -h 127.0.0.1 -U cinema_rw -d cinema -c "create table t_deny(x int)"
```

Phải báo `permission denied`. Thiếu `-h 127.0.0.1` thì psql đi qua Unix socket và xác thực kiểu peer, phép thử vô nghĩa.

## Backup

```text
pod postgres-1
 ├─ postgres ── mỗi file WAL đầy (hoặc sau tối đa 5 phút) ─┐
 └─ plugin-barman-cloud ───────────────────────────────────┴─▶ gs://cinema-<env>-pg-backup/postgres/
                                                                  ├─ wals/   WAL liên tục
ScheduledBackup postgres-nightly ── 02:00 mỗi đêm ──────────────▶ └─ base/   base backup
```

| File (`base/backup.yaml`)          | Việc                                                               |
| ---------------------------------- | ------------------------------------------------------------------ |
| ExternalSecret `postgres-backup`   | key service account từ GSM `infra-postgres-backup`, key `gcs.json` |
| ObjectStore `gcs`                  | bucket, credential, nén gzip, giữ 14 ngày (`retentionPolicy`)      |
| ScheduledBackup `postgres-nightly` | base backup 02:00 (giờ VN); `immediate` chụp bản đầu ngay khi tạo  |
| `Cluster.spec.plugins`             | bật WAL archiving qua plugin                                       |

Bucket của từng env khai ở `envs/<env>/kustomization.yaml`.

- Khôi phục được về **mọi thời điểm trong 14 ngày** (PITR): base backup gần nhất trước thời điểm đó + phát lại WAL tới đúng thời điểm.
- `retentionPolicy` do plugin tự xoá backup cũ; lifecycle 30 ngày của bucket chỉ là lưới an toàn.
- Thêm `plugins` vào `Cluster` làm pod Postgres khởi động lại một lần (để gắn container plugin). Còn 1 instance thì api mất kết nối DB vài chục giây.

### Verify backup

```bash
kubectl get cluster postgres -n infra -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'; echo   # True
kubectl get backup -n infra                                             # phase completed
gcloud storage ls gs://cinema-<env>-pg-backup/postgres/                 # base/ wals/
```

Chụp base backup ngay (ngoài lịch):

```bash
kubectl create -n infra -f - <<'YAML'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: postgres-manual-
spec:
  cluster:
    name: postgres
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
YAML
```

## Restore

Restore **luôn dựng `Cluster` mới** từ bucket, không ghi đè cluster đang chạy. Thử trước bằng tên khác (`postgres-restore`) để kiểm dữ liệu, rồi mới tính chuyện thay thế.

```bash
kubectl apply -n infra -f - <<'YAML'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restore
spec:
  instances: 1
  storage:
    size: 5Gi
  bootstrap:
    recovery:
      source: origin
      # Bỏ recoveryTarget để lấy tới WAL mới nhất.
      recoveryTarget:
        targetTime: "2026-10-01 10:00:00+07"
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: gcs
          serverName: postgres
YAML
```

- `serverName: postgres` là thư mục của cluster gốc trong bucket. Cluster restore **không** khai `plugins` WAL archiver trỏ cùng thư mục, nếu không nó ghi đè lịch sử WAL của cluster gốc.
- Kiểm dữ liệu: `kubectl exec -n infra postgres-restore-1 -c postgres -- psql -d cinema -c '\dt'`.
- Xong thì xoá: `kubectl delete cluster postgres-restore -n infra` (xoá cả PVC của nó).
- Cluster tạo tay như trên nằm ngoài Git: Argo CD không quản, cũng không xoá.

Thay hẳn cluster gốc bằng bản restore (mất database, dựng lại env) chưa thử: viết thành runbook sau lần diễn tập đầu tiên.

## Để dành sau

- HA: tăng `instances`. Mỗi replica tốn thêm ~50–75Mi RAM và 1 PVC. Giảm `instances` thì CNPG xoá instance số lớn nhất cùng PVC của nó.
- Thêm node: instance đang chạy không tự dời sang node mới (PVC `local-path` gắn với node cũ).
- Chưa có connection pooler.
