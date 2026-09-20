# Namespaces

> Argo CD tự apply. Không có bước tay nào.

`base/namespaces.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cinema
---
apiVersion: v1
kind: Namespace
metadata:
  name: infra
```

Namespace là cluster-scoped nên `destination.namespace` của Application không có ý nghĩa, chỉ để thỏa schema.

Namespace của operator (`argocd`, `cert-manager`, `cnpg-system`, `redis-operator`) do chart tự tạo qua `CreateNamespace=true`.

## Verify

```bash
kubectl get namespace cinema infra
```

## Cẩn thận

Xóa Namespace là xóa mọi thứ bên trong, gồm PVC của Postgres.
