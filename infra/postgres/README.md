# postgres

Postgres chạy bằng operator CloudNativePG (CNPG). Operator là chương trình theo dõi `Cluster` trong git và tự dựng Postgres theo đó: tạo pod, ổ đĩa, Service, role.

- Operator: ns `cnpg-system` (chart `cloudnative-pg`).
- Database: `Cluster postgres` ở ns `infra`, 1 instance, database `cinema`, ổ 5Gi.

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

## Để dành sau

- HA: tăng `instances`. Mỗi replica tốn thêm ~50–75Mi RAM và 1 PVC. Giảm `instances` thì CNPG xoá instance số lớn nhất cùng PVC của nó.
- Thêm node: instance đang chạy không tự dời sang node mới (PVC `local-path` gắn với node cũ).
- Chưa có connection pooler và backup.
