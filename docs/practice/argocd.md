Hiện tại bạn đang có

```text
VPS
 │
 └── k3s
      │
      └── Argo CD
           │
           └── root-staging
                │
                └── k8s/environments/staging/applications/
```

Điểm quan trọng: hiện tại gần như chưa có workload thật. Vì vậy đây là lúc rất an toàn để phá thử.

1. Mò Kubernetes trước
   Đầu tiên thử xem bạn đang có gì:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get namespaces
```

Sau đó:

```bash
kubectl describe node
```

Mục tiêu là hiểu:

```text
k3s
 └── Node
      ├── Pod
      ├── Service
      ├── Namespace
      └── ...
```

Đừng cần học hết Kubernetes ngay. Chỉ cần hiểu Node → Namespace → Pod → Service trước. 2. Mò Argo CD
Đây mới là thứ mình nghĩ bạn nên nghịch nhiều nhất.
Vào UI Argo CD và xem `root-staging`.
Tìm hiểu:

- `Sync`
- `Refresh`
- `Diff`
- `History`
- `Events`
- `Manifest`
- `Tree`

Đặc biệt thử hiểu sự khác nhau giữa:

```text
Git state
     vs
Cluster state
```

Đây chính là bản chất GitOps. 3. Thử tạo một Application cực nhỏ
Không cần Postgres, Redis hay Cinema.
Chỉ tạo:

```text
hello Application
```

Ví dụ:

```text
root-staging
    │
    └── hello
         │
         └── nginx
```

Sau đó push Git và quan sát:

```text
git push
   ↓
root-staging
   ↓
hello Application
   ↓
nginx Deployment
   ↓
Pod
```

Đây là bài thực hành đáng làm nhất ở thời điểm hiện tại. 4. Sau đó cố tình phá nó
Đây mới là phần thú vị.
Ví dụ Pod đang chạy:

```bash
kubectl get pods -A
```

Xóa Pod:

```bash
kubectl delete pod <pod-name> -n <namespace>
```

Rồi xem:

```bash
kubectl get pods -n <namespace> -w
```

Bạn sẽ thấy Kubernetes tự tạo Pod mới.
Điều này giúp phân biệt:
Kubernetes tự duy trì desired state
với:
Argo CD duy trì desired state từ Git.
Hai tầng này rất quan trọng. 5. Thử phá bằng `kubectl`
Ví dụ Git khai báo:

```text
replicas: 2
```

Bạn chạy:

```bash
kubectl scale deployment hello --replicas=5
```

Sau đó nhìn Argo CD.
Bạn sẽ thấy:

```text
Git       Cluster
  2   vs     5
       ↓
     OutOfSync
```

Nếu Application có:

```yaml
selfHeal: true
```

Argo CD sẽ đưa cluster về:

```text
replicas = 2
```

Đây là một trong những bài giúp hiểu GitOps nhanh nhất. 6. Thử `prune`
Tạo một Application con:

```text
hello.yaml
```

Push → Argo CD tạo nó.
Sau đó xóa `hello.yaml` khỏi Git.
Push.
Nếu root có:

```yaml
prune: true
```

Argo CD sẽ dọn resource tương ứng.
Bạn sẽ thấy rõ:

```text
Git
 ↓
resource tồn tại

Git xóa
 ↓
Argo CD prune
 ↓
resource biến mất
```

7. Mò `kubectl` vs Argo CD
   Đây là thứ rất đáng hiểu trước Giai đoạn 3.
   `kubectl`
   Bạn đang nói trực tiếp với Kubernetes:

```text
Bạn → kubectl → Kubernetes
```

Argo CD

```text
Bạn → Git → Argo CD → Kubernetes
```

Và từ đây:
Git là nơi bạn thay đổi hệ thống, Kubernetes là nơi hệ thống chạy.
`kubectl` chủ yếu để:

```text
observe
debug
inspect
```

thay vì dùng để thay đổi production state bằng tay. 8. Mò Kubernetes namespace
Bạn có thể tự tạo thử một namespace bằng Git.
Sau đó xem:

```bash
kubectl get ns
```

Rồi thử:

```bash
kubectl get all -n <namespace>
```

Mục tiêu là hiểu:

```text
Cluster
│
├── argocd
│    ├── pods
│    ├── services
│    └── ...
│
└── hello
     ├── deployment
     ├── pod
     └── service
```

Sau này Platform sẽ dựa rất nhiều vào namespace. 9. Mò Networking
Đây cũng là thời điểm tốt để thử.
Tạo một nginx:

```text
Pod
 ↓
Service
```

Sau đó tìm hiểu:

```bash
kubectl get svc
kubectl describe svc <name>
```

Rồi thử:

```bash
kubectl port-forward ...
```

Bạn sẽ bắt đầu hiểu:

```text
Browser
   ↓
Ingress
   ↓
Service
   ↓
Pod
```

Sau này đến Traefik sẽ dễ hiểu hơn rất nhiều.
Nếu chỉ chọn 5 thứ để mò
Mình sẽ chọn đúng thứ tự này:

```text
① kubectl get / describe / logs
             ↓
② tạo Hello Application qua Git
             ↓
③ Git → Argo CD → Kubernetes
             ↓
④ cố tình kubectl sửa cluster
             ↓
⑤ xem selfHeal + prune sửa lại
```

Sau 5 bài này, bạn sẽ hiểu được tại sao Giai đoạn 2 tồn tại, chứ không chỉ biết cách copy YAML.
Và có một thứ mình KHÔNG khuyên mò ngay
Chưa cần đụng:

```text
❌ Postgres
❌ Redis
❌ cert-manager
❌ Sealed Secrets
❌ Production
❌ CI/CD
❌ Helm phức tạp
```

Vì chúng sẽ thêm rất nhiều biến số.
Hiện tại hệ thống của bạn đang ở trạng thái "laboratory sạch":

```text
VPS
 ↓
k3s
 ↓
Argo CD
 ↓
App-of-Apps
 ↓
[chưa có app thật]
```

Đây là thời điểm đẹp nhất để phá thử. Một khi thêm Postgres + Redis + Traefik + cert-manager thì debug sẽ khó hơn rất nhiều.
