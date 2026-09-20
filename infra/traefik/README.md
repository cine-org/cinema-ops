# Traefik: đường vào từ Internet

Mục tiêu: hiểu request từ trình duyệt đi vào pod bằng đường nào, và bắt mọi request HTTP chuyển sang HTTPS.

Traefik **đi kèm k3s**, không cài gì thêm. Thư mục này chỉ chứa một file cấu hình đè lên bản có sẵn.

## Đường đi của một request

```text
Trình duyệt  https://cine.io.vn
     │
     ▼  DNS Cloudflare (DNS only) → IP của VPS
Cổng 443 của VPS
     │
     ▼  Service svclb của k3s đưa cổng 80/443 vào cluster
Traefik (ns kube-system)
     │  cắt TLS ở đây, dùng Secret cine-io-vn-tls
     │  đọc Ingress: host nào thì đi Service nào
     ▼
Service web-user (ClusterIP)
     │
     ▼
Pod web-user :80
```

Hai điều đáng nhớ:

- **Service kiểu ClusterIP chỉ tới được từ trong cluster.** Ingress là đường duy nhất từ Internet vào. Không tạo Ingress cho api thì api vẫn chạy và các pod khác vẫn gọi được, chỉ Internet là không.
- **TLS được cắt ở Traefik.** Từ Traefik vào pod là HTTP thường, trong mạng nội bộ của cluster.

## Cloudflare làm gì

Hiện đặt **DNS only**, tức Cloudflare chỉ trả lời "cine.io.vn ở IP này" rồi thôi, mọi thứ còn lại nằm ở VPS.

Nếu bật proxy (đám mây cam) thì request đi qua Cloudflare: có CDN, chống DDoS, ẩn IP VPS. Khi đó phải đặt SSL mode là **Full (strict)**, nghĩa là Cloudflare vẫn kiểm chứng chỉ của VPS, nên vẫn cần cert-manager. Chưa bật vì thêm một tầng nữa lúc đang học là thêm chỗ để đoán mò khi hỏng.

Bản ghi DNS cần có, kiểu A, trỏ về IP VPS: `cine.io.vn`, `admin.cine.io.vn`, và sau này `api.cine.io.vn`.

## Chuyển HTTP sang HTTPS

`base/helmchartconfig.yaml`:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |
    ports:
      web:
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
              permanent: true
```

**`HelmChartConfig` là cách k3s cho phép đè values của chart có sẵn.** Tên phải đúng bằng `traefik` và namespace phải là `kube-system` để khớp với `HelmChart` mà k3s tạo sẵn. Apply xong, k3s chạy lại job `helm-install-traefik` để upgrade release, Traefik khởi động lại vài giây.

Chuyển hướng đặt ở **entrypoint**, nên áp cho mọi host, kể cả host chưa có Ingress. Cách khác là gắn middleware vào từng Ingress, phải nhớ lặp lại mỗi lần thêm app.

`permanent: true` cho Traefik trả 301 với GET và 308 với các method khác. Cả hai đều là "chuyển vĩnh viễn"; 308 giữ nguyên method và body, còn 301 thì lịch sử cho phép client đổi POST thành GET.

Chuyển hướng này không cản việc cert-manager xin chứng chỉ: Let's Encrypt đi theo redirect sang HTTPS và vẫn đọc được nội dung challenge.

## Bài học: sai một cấp khóa là im lặng không chạy

Lần đầu viết là `ports.web.redirections`, thiếu cấp `http`. Chart Traefik 40 đọc `ports.web.http.redirections`, nên values kia bị **bỏ qua hoàn toàn**: không lỗi, không cảnh báo, Application vẫn `Synced`, chỉ HTTP vẫn trả 200 như cũ.

Cách kiểm tra đúng không phải là grep manifest, mà là hỏi thẳng release và pod:

```bash
helm get values traefik -n kube-system
kubectl get pod -n kube-system -l app.kubernetes.io/name=traefik \
  -o jsonpath='{.items[0].spec.containers[0].args}' | tr ',' '\n' | grep -i redirect
```

Phải thấy đối số `--entryPoints.web.http.redirections.entryPoint.to=websecure`. Không thấy dòng đó thì values chưa tới được Traefik, dù Git trông rất đúng.

## Verify

```bash
kubectl get helmchartconfig -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
curl -sI http://cine.io.vn | head -3
```

Phải thấy `301` hoặc `308` kèm `location: https://...`. Rồi thử:

```bash
curl -sI https://cine.io.vn | head -3
```

Phải `200` và không có cảnh báo chứng chỉ.

Xem Traefik hiểu Ingress thế nào thì mở dashboard của nó:

```bash
kubectl port-forward -n kube-system deploy/traefik 9000:9000
```

Rồi vào `http://localhost:9000/dashboard/`.

## Để dành sau

nginx cũ bên `cinema` (`infrastructure/nginx`) có vài thứ chưa chuyển sang đây. Mỗi cái là một `Middleware` của Traefik, gắn vào Ingress qua annotation:

| nginx cũ | Tương đương ở Traefik |
| --- | --- |
| `limit_req 10r/s` cho api | `Middleware` loại `rateLimit` |
| security header | `Middleware` loại `headers` |
| `gzip on` | `Middleware` loại `compress` |
| `client_max_body_size 20M` | `Middleware` loại `buffering` |
| trả 444 cho host lạ | Traefik trả 404 mặc định, muốn khác thì thêm router bắt tất |

---

Tiếp: [kéo image private từ GHCR](../ghcr-pull/README.md).
