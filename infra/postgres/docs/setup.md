# Postgres (CNPG)

> Cần `infra-postgres`, `infra-postgres-rw`, `infra-postgres-ro` trên GSM trước.

Operator ở ns `cnpg-system`, database ở ns `infra`. Application 2 source: chart + `envs/staging`; CR mang `sync-wave: "1"` để chờ operator.

## Phải nhớ

- `bootstrap.initdb` chỉ chạy **một lần** lúc cluster rỗng, sửa sau không tạo lại database.
- `inherit: true` và `connectionLimit: -1` đúng bằng default nhưng **vẫn phải khai**: webhook điền chúng vào từng phần tử `managed.roles`, thiếu trong Git là OutOfSync vĩnh viễn (default rơi vào list thì Argo so nguyên cụm list).
- `passwordSecret` trỏ Secret có key `username` **đúng bằng tên role**, type `basic-auth`. Secret dùng gạch ngang (`infra-postgres-rw`), role dùng gạch dưới (`cinema_rw`); sai thì CNPG bỏ qua role mà Cluster vẫn `Healthy`.
- `pg_read_all_data` / `pg_write_all_data` áp quyền động nên bảng migration tạo sau tự được phủ. Không gồm `TRUNCATE`.
- Không khai `storageClass` → `local-path`, PVC không co lại được, 5Gi là sàn.
- Không đặt `limits.cpu`: vượt CPU chỉ throttle, RAM mới cần chặn cứng.

## Verify

```bash
kubectl get cluster -n infra                 # Cluster in healthy state
kubectl exec -it -n infra postgres-1 -- psql -U postgres -d cinema -c '\du'
```

Phân quyền phải thử bằng lệnh thật, `\du` không đủ:

```bash
PW=$(kubectl get secret infra-postgres-rw -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra postgres-1 -c postgres -- env PGPASSWORD="$PW" \
  psql -h 127.0.0.1 -U cinema_rw -d cinema \
  -c "insert into t_check(note) values ('ok')" -c "create table t_deny(x int)"
```

`insert` phải chạy, `create table` phải `permission denied`. Thiếu `-h 127.0.0.1` thì psql đi Unix socket, xác thực peer, phép thử vô nghĩa.

Role không hiện → `kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'`.

## Để dành sau

- HA: tăng `instances`, mỗi replica ~50–75Mi RAM + 1 PVC; giảm thì CNPG xóa instance số lớn nhất cùng PVC.
- Thêm node: instance đang chạy không tự dời (PVC `local-path` gắn node cũ), phải xóa cả PVC lẫn pod của replica.
- Chưa có Pooler và backup.
