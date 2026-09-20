# cert-manager

> Chart cài 3 pod: controller (xin + gia hạn), webhook (validate YAML), cainjector (bơm CA cho webhook của operator khác). Đo thực tế ~82Mi.

- **`crds.enabled: true` bắt buộc**: chart mặc định không cài CRD.
- `crds.keep` mặc định `true`: xóa Application thì `Certificate` vẫn còn.
- **Thử `letsencrypt-staging` trước.** Bản prod giới hạn số lần xin mỗi tuần cho một tên miền, sai cấu hình mà thử lại nhiều lần là bị chặn vài ngày.
- Không khai `email`: đổi lại không nhận thư nhắc hết hạn, nhưng cert-manager đã tự gia hạn.
- `privateKeySecretRef` là khóa **tài khoản ACME**, không phải khóa chứng chỉ.

## HTTP-01 chạy thế nào

```text
Ingress có annotation → Certificate → cert-manager tạo Ingress tạm cho
http://<host>/.well-known/acme-challenge/<token> → Let's Encrypt gọi vào cổng 80
→ khớp → ghi Secret <host>-tls
```

Nên **cổng 80 phải mở và DNS phải trỏ đúng IP**. Redirect 80→443 không cản: Let's Encrypt đi theo redirect.

DNS-01 chỉ cần khi muốn chứng chỉ wildcard, phải đưa token API của DNS cho cluster.

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
kubectl get pods -n cert-manager
kubectl get clusterissuer            # READY True
kubectl get certificate -A           # READY True
```

Kẹt thì lần ngược chuỗi:

```bash
kubectl describe certificate <tên> -n <ns>
kubectl get certificaterequest,order,challenge -n <ns>
kubectl describe challenge <tên> -n <ns>
```

`Challenge` thường kẹt vì DNS sai IP hoặc cổng 80 bị chặn.

Xem chứng chỉ thật:

```bash
kubectl get secret cine-io-vn-tls -n cinema -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -issuer -dates
```
