# cert-manager

Mục tiêu: cluster tự xin và tự gia hạn chứng chỉ TLS, để web chạy HTTPS mà không ai phải nhớ ngày hết hạn.

## Khái niệm

**Chứng chỉ** gồm khóa riêng (giữ bí mật) và giấy xác nhận "khóa này thuộc về tên X", có chữ ký của một bên ký. Bên ký có thể là:

- **CA nội bộ hoặc tự ký**: chỉ thành phần nào được cấu hình tin CA đó mới tin. Đủ cho webhook giữa các thành phần trong cluster.
- **Let's Encrypt**: mọi trình duyệt đều tin. Dùng cho website.

Chứng chỉ có hạn dùng. cert-manager tự gia hạn trước khi hết hạn, đó là lý do chính để dùng nó thay vì tạo tay bằng `openssl`.

| Kind | Nghĩa |
| --- | --- |
| `Issuer` | ai ký, chỉ dùng trong namespace của nó |
| `ClusterIssuer` | như `Issuer` nhưng mọi namespace đều dùng được |
| `Certificate` | cần chứng chỉ cho tên X, do Issuer Y ký, lưu vào Secret Z |
| `CertificateRequest`, `Challenge`, `Order` | cert-manager tự sinh trong lúc làm việc, để lần theo khi hỏng |

Kết quả cuối cùng là một Secret kiểu `kubernetes.io/tls` chứa `tls.crt` và `tls.key`. Traefik đọc Secret đó.

Chart cài ba pod:

```text
cert-manager             thấy Certificate → nhờ Issuer ký → ghi Secret, tự gia hạn
cert-manager-webhook     kiểm tra YAML Certificate/Issuer trước khi K8s lưu
cert-manager-cainjector  chép CA vào cấu hình webhook của operator khác
```

**Webhook** ở đây nghĩa là: khi apply một custom resource, API server gọi HTTPS sang operator hỏi "YAML này hợp lệ không?" trước khi lưu. Vì là HTTPS nên operator phải có chứng chỉ. CNPG và redis-operator tự sinh lấy; những operator khác giao việc đó cho cert-manager qua annotation `cert-manager.io/inject-ca-from`.

## Wiring

```text
clusters/staging/infra/cert-manager.yaml   Application "cert-manager", 2 source:
  ├── chart cert-manager v1.21.2 → ns cert-manager
  └── infra/cert-manager/envs/staging → 2 ClusterIssuer (sync-wave 1)
```

Trong `values.yaml`:

- **`crds.enabled: true` là bắt buộc.** Chart mặc định **không** cài CRD; thiếu dòng này thì K8s không biết `Certificate` là gì.
- `crds.keep` mặc định `true`: xóa Application thì CRD và mọi `Certificate` vẫn còn, tránh mất chứng chỉ vì lỡ tay.
- `resources` khai cho cả ba pod, tổng request khoảng 160Mi. Đo thực tế lúc chạy khoảng 82Mi.

## ClusterIssuer

`base/cluster-issuers.yaml` khai hai cái, cùng cấu hình, khác mỗi địa chỉ máy chủ:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

Cái thứ hai tên `letsencrypt-prod`, `server` là `https://acme-v02.api.letsencrypt.org/directory`, `privateKeySecretRef` là `letsencrypt-prod-account`.

- **Luôn thử `letsencrypt-staging` trước.** Let's Encrypt bản production giới hạn số lần xin mỗi tuần cho một tên miền; sai cấu hình mà thử đi thử lại là bị chặn nhiều ngày. Chứng chỉ từ staging thì trình duyệt báo không tin, đúng như mong đợi: mục đích chỉ là xác nhận quy trình chạy được.
- `privateKeySecretRef` là khóa **tài khoản ACME**, không phải khóa chứng chỉ. cert-manager tự tạo nếu chưa có.
- Không khai `email`. Không có email thì không nhận được thư nhắc hết hạn, nhưng cert-manager đã tự gia hạn nên chấp nhận được, đổi lại không phải đưa email cá nhân cho Let's Encrypt.

## HTTP-01: chứng chỉ được cấp thế nào

```text
1. Ingress có annotation cert-manager.io/cluster-issuer → cert-manager tạo Certificate
2. cert-manager xin Let's Encrypt cấp cho cine.io.vn
3. Let's Encrypt: "chứng minh anh làm chủ tên miền đó"
4. cert-manager tạo tạm một Ingress phục vụ http://cine.io.vn/.well-known/acme-challenge/<token>
5. Let's Encrypt gọi vào đường dẫn đó qua cổng 80
6. Khớp → cấp chứng chỉ → cert-manager ghi vào Secret cine-io-vn-tls
7. Ingress thật dùng Secret đó, xóa Ingress tạm
```

Vì thế **cổng 80 phải mở ra Internet và DNS phải trỏ đúng IP** trước khi xin chứng chỉ. Chuyển hướng 80 sang 443 không cản trở: Let's Encrypt đi theo chuyển hướng, và nội dung challenge vẫn đọc được qua HTTPS.

Cách khác là DNS-01 (chứng minh bằng bản ghi TXT), bắt buộc nếu muốn chứng chỉ wildcard, nhưng phải cấp token API của nhà cung cấp DNS cho cluster. Hiện chưa cần.

## Dùng ở Ingress

Không viết `Certificate` bằng tay. Gắn annotation vào Ingress là cert-manager tự tạo:

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
kubectl get clusterissuer
kubectl get certificate -A
```

Xong khi: ba pod Running, cả hai `ClusterIssuer` `READY=True`, và mỗi Ingress có TLS đều có một `Certificate` `READY=True`.

Chứng chỉ kẹt thì lần ngược chuỗi:

```bash
kubectl describe certificate <tên> -n <ns>
kubectl get certificaterequest,order,challenge -n <ns>
kubectl describe challenge <tên> -n <ns>
```

`Challenge` thường kẹt vì DNS chưa trỏ đúng IP, hoặc cổng 80 bị tường lửa chặn.

Xem chứng chỉ thật đang dùng:

```bash
kubectl get secret cine-io-vn-tls -n cinema -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -subject -issuer -dates
```

## Thử cấp một chứng chỉ tự ký

Bài tập ngắn để thấy cơ chế `Issuer` → `Certificate` → `Secret`, không đụng gì tới Let's Encrypt. Làm trong namespace riêng rồi xóa.

```bash
kubectl create namespace cm-test
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned
  namespace: cm-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo
  namespace: cm-test
spec:
  secretName: demo-tls
  dnsNames:
    - demo.cm-test.svc
  duration: 24h
  renewBefore: 1h
  issuerRef:
    name: selfsigned
    kind: Issuer
EOF
kubectl get issuer,certificate,secret -n cm-test
```

Thử self-heal bằng cách xóa Secret `demo-tls`: cert-manager cấp lại ngay. Dọn bằng `kubectl delete namespace cm-test`.

## Để dành sau

- Chứng chỉ wildcard qua DNS-01, nếu số subdomain tăng.
- `Certificate` cho webhook của operator khác, khi có operator cần nó (RabbitMQ chẳng hạn).

---

Tiếp: [Traefik](../traefik/README.md).
