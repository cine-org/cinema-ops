# barman-cloud

Plugin backup của CloudNativePG (chart `plugin-barman-cloud`). Plugin đẩy WAL và base backup của Postgres lên object storage, và đọc lại khi restore. Cấu hình backup nằm ở [infra/postgres](../postgres/README.md); thư mục này chỉ cài plugin.

- Chạy ở ns `cnpg-system`, **bắt buộc** cùng ns với operator CNPG.
- Cần cert-manager: plugin nói chuyện với operator qua gRPC có TLS, chứng chỉ do cert-manager cấp.
- Mang theo CRD `ObjectStore` (`barmancloud.cnpg.io`).
- Khi một `Cluster` khai plugin, operator gắn thêm container `plugin-barman-cloud` vào pod Postgres; container đó mới là thứ ghi lên bucket.

Version chart phải hợp với operator CNPG (plugin cần CNPG ≥ 1.26). Nâng operator thì đọc release notes của plugin trước.

## Verify

```bash
kubectl get deploy -n cnpg-system plugin-barman-cloud     # 1/1
kubectl get crd objectstores.barmancloud.cnpg.io
```
