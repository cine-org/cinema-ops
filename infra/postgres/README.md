# Postgres: CloudNativePG

Mục tiêu: một instance Postgres trong namespace `infra`, database `cinema`, credential kéo từ Google Secret Manager. Không tạo secret tay, không viết StatefulSet tay.

CNPG là operator: cài một lần, cluster có thêm CRD `Cluster`. Khai `Cluster` ngắn gọn, operator tự dựng StatefulSet, PVC, Service và lo failover phía sau.

## Cần có trước

- [external-secrets](../external-secrets/README.md) đã chạy, và bên GSM đã có `infra-postgres`, `infra-postgres-rw`, `infra-postgres-ro`.

## Wiring

```text
clusters/staging/infra/postgres.yaml   Application "postgres", 2 source:
  ├── chart cloudnative-pg 0.29.0 → ns cnpg-system   (helm.releaseName: cnpg-operator)
  └── infra/postgres/envs/staging     → Cluster + ExternalSecret, ns infra
```

Operator nằm riêng ở `cnpg-system`, database nằm ở `infra`. Custom resource mang `sync-wave: "1"` nên Argo CD chờ operator khỏe rồi mới apply `Cluster`.

`helm.releaseName: cnpg-operator` ghim tên release Helm. Không có nó thì Argo CD lấy tên Application (`postgres`) làm tên release, và chart sinh ra một bộ tài nguyên mang tên mới.

## File

### `base/external-secrets.yaml`

Ba `ExternalSecret`: owner, rw, ro. Cái owner:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: infra-postgres
  namespace: infra
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: infra-postgres
  data:
    - secretKey: username
      remoteRef: {key: infra-postgres, property: username}
    - secretKey: password
      remoteRef: {key: infra-postgres, property: password}
```

`username` và `password` là hai tên CNPG bắt buộc. Hai cái còn lại y hệt, chỉ thêm `target.template.type: kubernetes.io/basic-auth` vì `managed.roles` đòi đúng type đó.

### `base/cluster.yaml`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
  namespace: infra
spec:
  instances: 1

  bootstrap:
    initdb:
      database: cinema
      owner: cinema
      secret:
        name: infra-postgres

  managed:
    roles:
      - name: cinema_rw
        ensure: present
        login: true
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: infra-postgres-rw
        inRoles:
          - pg_read_all_data
          - pg_write_all_data

      - name: cinema_ro
        ensure: present
        login: true
        inherit: true
        connectionLimit: -1
        passwordSecret:
          name: infra-postgres-ro
        inRoles:
          - pg_read_all_data

  storage:
    size: 5Gi

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
```

- `bootstrap.initdb` **chỉ chạy một lần**, lúc cluster còn rỗng. Sửa về sau không tạo lại database.
- `inherit: true` và `connectionLimit: -1` đúng bằng giá trị mặc định, nhưng vẫn phải khai. Webhook của CNPG điền chúng vào từng phần tử của `managed.roles`; thiếu trong Git thì Argo CD `OutOfSync` vĩnh viễn. Đây là bẫy chung: default rơi vào **map** thì vô hại vì Argo CD chỉ so field mình khai, nhưng rơi vào phần tử của **list** thì Argo CD so nguyên cụm list.
- Không khai `storageClass` nên dùng mặc định của k3s là `local-path`, tức đĩa của VPS. PVC không co lại được, nên 5Gi là sàn.
- Không đặt `limits.cpu`: vượt CPU chỉ bị throttle, còn RAM mới cần chặn cứng để khỏi làm chết cả node.
- `imageName` để trống nên lấy version Postgres mặc định của operator.

## Ba role

| Role | Do đâu tạo | Dùng cho |
| --- | --- | --- |
| `cinema` | `initdb`, là owner | migration, DDL |
| `cinema_rw` | `managed.roles` | api: đọc và ghi dữ liệu |
| `cinema_ro` | `managed.roles` | báo cáo, đọc thuần |

- `pg_read_all_data` và `pg_write_all_data` là predefined role có sẵn từ Postgres 14. Quyền áp **động** lúc truy cập, nên bảng do migration tạo sau này tự được phủ. Nhờ vậy không cần Job chạy `GRANT` kèm `ALTER DEFAULT PRIVILEGES`.
- `passwordSecret` phải trỏ tới Secret có key `username` **đúng bằng tên role**, type `kubernetes.io/basic-auth`. Chú ý hai hệ tên nằm cạnh nhau: tên Secret và GSM dùng gạch ngang (`infra-postgres-rw`, vì K8s không cho gạch dưới), còn tên role dùng gạch dưới (`cinema_rw`). Ghi nhầm `cinema-rw` vào `username` thì CNPG từ chối tạo role nhưng `Cluster` vẫn `Healthy`; lý do chỉ hiện trong `status.managedRolesStatus`.
- `pg_write_all_data` **không** gồm `TRUNCATE`. `cinema_rw` xóa sạch bảng bằng `DELETE FROM` được, bằng `TRUNCATE` thì bị chặn; script seed dùng `TRUNCATE` phải chạy bằng `cinema`.
- Khác `initdb`, role ở đây có đổi password theo Secret. CNPG lưu `resourceVersion` của Secret trong `status.managedRolesStatus.passwordStatus`, nhưng chỉ áp vào lần reconcile kế tiếp. Muốn có ngay thì ép: `kubectl rollout restart deployment cnpg-operator-cloudnative-pg -n cnpg-system`.

## Kết nối từ app

| Service (ns `infra`) | Dùng cho |
| --- | --- |
| `postgres-rw` | đọc và ghi, luôn trỏ primary — mặc định |
| `postgres-ro` | chỉ đọc, chỉ replica (hiện chưa có replica) |
| `postgres-r` | chỉ đọc, mọi instance |

```text
postgresql://cinema_rw:<pw>@postgres-rw.infra.svc:5432/cinema
```

Secret không dùng chéo namespace, nên app ở `cinema` cần `ExternalSecret` riêng trỏ về cùng key GSM.

## Verify

```bash
kubectl get pods -n cnpg-system
kubectl get externalsecret -n infra
kubectl get cluster -n infra
kubectl get pods -n infra -l cnpg.io/cluster=postgres
kubectl exec -it -n infra postgres-1 -- psql -U postgres -d cinema -c '\du'
```

Xong khi: `externalsecret` là `SecretSynced`, cột `STATUS` của cluster là `Cluster in healthy state`, pod `postgres-1` Running, và `\du` thấy đủ `cinema`, `cinema_rw`, `cinema_ro`.

Phân quyền phải thử bằng câu lệnh thật, nhìn `\du` không đủ:

```bash
kubectl exec -n infra postgres-1 -c postgres -- \
  psql -U postgres -d cinema -c 'create table if not exists t_check(id serial primary key, note text)'

PW=$(kubectl get secret infra-postgres-rw -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra postgres-1 -c postgres -- env PGPASSWORD="$PW" \
  psql -h 127.0.0.1 -U cinema_rw -d cinema \
  -c "insert into t_check(note) values ('ok') returning id" \
  -c "create table t_deny(x int)"
```

`insert` phải chạy được, chứng minh có quyền trên sequence của `serial`, chỗ hay hụt. `create table` phải báo `permission denied`. Làm tương tự với `cinema_ro`: `select` chạy, `insert` bị chặn. Dọn bằng `drop table t_check`.

Bắt buộc có `-h 127.0.0.1`. Thiếu nó thì psql nối qua Unix socket và xác thực bằng peer, không kiểm tra password, nên phép thử vô nghĩa.

Role không xuất hiện thì xem lý do ở:

```bash
kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'; echo
```

`cannotReconcile` là CNPG từ chối tạo role và ghi lý do. `Cluster` vẫn `Healthy` nên `kubectl get cluster` không hé lộ gì.

Cuối cùng thử dữ liệu có bền qua restart: ghi một dòng, `kubectl delete pod postgres-1 -n infra`, chờ pod lên rồi đọc lại. PVC cũ phải được gắn lại và dòng đó còn nguyên.

## Để dành sau

- **HA**: tăng `instances` là operator tự lo replication. Đo trên staging: mỗi replica thêm khoảng 50–75Mi RAM lúc rảnh và một PVC bằng `storage.size`. Giảm về thì CNPG xóa instance số lớn nhất cùng PVC của nó.
- **Thêm node**: CNPG có sẵn `podAntiAffinity` loại `preferred` nên instance **mới** tự tránh node đã có instance. Instance **đang chạy** không tự dời, vì PVC `local-path` gắn chặt vào node cũ; phải xóa cả PVC lẫn pod của một replica để CNPG dựng lại ở node khác. Làm lần lượt từng replica rồi switchover primary.
- **Pooler (PgBouncer)**: cần khi số kết nối từ app tăng.
- **Backup** (`spec.backup` ra object storage): làm trước khi có dữ liệu thật.

---

Tiếp: [Redis](../redis/README.md).
