# Namespaces

Mục tiêu: tạo hai namespace nền cho môi trường.

| Namespace | Chứa gì |
| --- | --- |
| `cinema` | app của repo `cinema`: web-user, web-admin, sau này api, worker, scheduler |
| `infra` | hạ tầng dùng chung: Postgres, Redis, External Secrets |

## Khái niệm

**Namespace** chia cluster thành nhiều ngăn. Tên tài nguyên chỉ cần duy nhất trong một namespace, nên hai namespace có thể cùng có Service tên `api`. Quan trọng hơn: **Secret không dùng chéo namespace**. Pod ở `cinema` không đọc được Secret ở `infra`, dù cả hai cùng cluster. Vì vậy app cần mật khẩu Postgres thì phải có `ExternalSecret` riêng trong `cinema`, trỏ về cùng một secret bên Google Secret Manager.

Namespace là tài nguyên cluster-scoped, không nằm trong namespace nào. `destination.namespace` của Application này không có ý nghĩa gì, chỉ để thỏa schema bắt buộc của Argo CD.

Những namespace khác (`argocd`, `cert-manager`, `cnpg-system`, `redis-operator`) do chính chart của chúng tạo qua `CreateNamespace=true`, không khai ở đây.

## File

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

Application tương ứng: `clusters/staging/infra/namespaces.yaml`.

## Verify

```bash
kubectl get namespace cinema infra
```

## Cẩn thận

Xóa một Namespace là xóa **mọi thứ bên trong**, gồm cả PVC chứa dữ liệu Postgres. Khi đổi tên namespace, đừng xóa cái cũ cho tới khi cái mới chạy xong và dữ liệu đã chuyển.

---

Tiếp: [secret từ Google Secret Manager](../external-secrets/README.md).
