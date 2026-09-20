# Namespaces

> Argo CD tự apply, không có bước tay.

`cinema` (app) và `infra` (Postgres, Redis, ESO). Namespace của operator do chart tự tạo qua `CreateNamespace=true`.

Namespace là cluster-scoped nên `destination.namespace` của Application không có ý nghĩa, chỉ để thỏa schema.

```bash
kubectl get namespace cinema infra
```

Xóa Namespace là xóa mọi thứ bên trong, gồm PVC của Postgres.
