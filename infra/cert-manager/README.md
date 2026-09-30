# cert-manager

Xin chứng chỉ TLS từ Let's Encrypt và tự gia hạn trước khi hết hạn.

Chart cài 3 pod:

| Pod        | Việc                                                       |
| ---------- | ---------------------------------------------------------- |
| controller | xin và gia hạn chứng chỉ                                   |
| webhook    | kiểm tra YAML của `Certificate`, `ClusterIssuer` khi apply |
| cainjector | gắn CA vào webhook của các operator khác                   |

`base/cluster-issuers.yaml` có 2 `ClusterIssuer`, dùng chung cho mọi namespace:

- `letsencrypt-staging`: để thử, chứng chỉ không được trình duyệt tin;
- `letsencrypt-prod`: chứng chỉ thật.

## Dùng ở Ingress

Thêm annotation và khối `tls`, không viết `Certificate` bằng tay:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts: [api.staging.cine.io.vn]
      secretName: api-staging-cine-io-vn-tls
```

cert-manager thấy annotation thì tự tạo `Certificate` và ghi chứng chỉ vào secret `secretName`.

## Let's Encrypt kiểm tra tên miền thế nào (HTTP-01)

```text
cert-manager dựng Ingress tạm: http://<host>/.well-known/acme-challenge/<token>
  ─▶ Let's Encrypt gọi vào cổng 80 của host
  ─▶ đúng token ─▶ cấp chứng chỉ ─▶ ghi vào Secret
```

Cần DNS của host trỏ đúng IP VPS và cổng 80 mở. Redirect HTTP sang HTTPS (`infra/traefik`) không cản, Let's Encrypt đi theo redirect.

## Phải nhớ

- `crds.enabled: true` là bắt buộc: chart mặc định không cài CRD. Xoá app thì CRD và `Certificate` vẫn còn (`crds.keep` mặc định `true`).
- Host mới thì thử `letsencrypt-staging` trước: bản prod giới hạn số lần xin mỗi tuần cho một tên miền.
- Không khai `email`: chỉ mất thư nhắc sắp hết hạn, mà cert-manager đã tự gia hạn.
- `privateKeySecretRef` giữ khoá **tài khoản ACME**, không phải khoá của chứng chỉ.
- `ClusterIssuer` có `sync-wave: "1"` để chờ chart cài CRD xong.

## Verify

```bash
kubectl get clusterissuer            # READY True
kubectl get certificate -A           # READY True
```

`Certificate` kẹt ở `False` thì lần theo thứ tự:

1. `kubectl describe certificate <tên> -n <ns>`
2. `kubectl get certificaterequest,order,challenge -n <ns>`
3. `kubectl describe challenge <tên> -n <ns>`

Nguyên nhân thường là DNS trỏ sai IP hoặc cổng 80 bị chặn.
