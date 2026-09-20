# cert-manager

> Chart cài 3 pod: controller (xin + gia hạn), webhook (validate YAML), cainjector (bơm CA cho webhook của operator khác). Đo thực tế ~82Mi.

- **`crds.enabled: true` bắt buộc**: chart mặc định không cài CRD.
- `crds.keep` mặc định `true`: xóa Application thì `Certificate` vẫn còn.
- **Thử `letsencrypt-staging` trước**: bản prod giới hạn số lần xin mỗi tuần cho một tên miền.
- Không khai `email`: mất thư nhắc hết hạn, nhưng cert-manager đã tự gia hạn.
- `privateKeySecretRef` là khóa **tài khoản ACME**, không phải khóa chứng chỉ.

## HTTP-01

```text
Ingress có annotation → Certificate → cert-manager dựng Ingress tạm cho
http://<host>/.well-known/acme-challenge/<token> → Let's Encrypt gọi vào cổng 80
→ khớp → ghi Secret <host>-tls
```

Nên cổng 80 phải mở và DNS phải trỏ đúng IP. Redirect 80→443 không cản, Let's Encrypt đi theo redirect. DNS-01 chỉ cần khi muốn wildcard.

## Dùng ở Ingress

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts: [cine.io.vn]
      secretName: cine-io-vn-tls
```

## Verify

```bash
kubectl get clusterissuer            # READY True
kubectl get certificate -A           # READY True
```

Kẹt thì lần ngược: `describe certificate` → `get certificaterequest,order,challenge` → `describe challenge`. Thường vì DNS sai IP hoặc cổng 80 bị chặn.

```bash
kubectl get secret cine-io-vn-tls -n cinema -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -issuer -dates
```
