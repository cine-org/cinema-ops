# Cheatsheet

Lệnh hay dùng và vài bài tập để hiểu GitOps. Chạy trên VPS, hoặc từ máy local qua `ssh cinema-prod '<lệnh>'`.

## Nhìn tổng thể

```bash
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
```

Ba lệnh này trả lời: máy còn sống không, cái gì đang chạy, Git và cluster có khớp nhau không.

```bash
kubectl get pods -n <ns> -o wide      # pod nằm node nào, IP gì
kubectl describe pod <pod> -n <ns>    # sự kiện: vì sao Pending, vì sao bị kill
kubectl logs <pod> -n <ns> -f         # log đang chảy
kubectl logs <pod> -n <ns> --previous # log của lần chạy trước khi crash
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

Pod không lên thì xem theo thứ tự: `get pods` (trạng thái) → `describe` (sự kiện) → `logs` (ứng dụng nói gì).

## Argo CD

```bash
kubectl get app -n argocd
kubectl describe app <tên> -n argocd            # lý do OutOfSync nằm ở đây
kubectl get app <tên> -n argocd -o jsonpath='{.status.conditions}'; echo
```

Ép Argo CD đọc lại Git ngay thay vì chờ chu kỳ 3 phút:

```bash
kubectl annotate app <tên> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

Mở UI: trên VPS chạy `kubectl -n argocd port-forward svc/argocd-server 8080:443`, trên máy local chạy `ssh -L 8080:localhost:8080 cinema-prod`, rồi vào `https://localhost:8080`.

Mật khẩu admin ban đầu:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Kiểm tra trước khi push

Render kustomize để xem Argo CD sẽ apply đúng cái gì:

```bash
kubectl kustomize infra/postgres/envs/staging
```

So với cluster đang chạy, không đổi gì:

```bash
kubectl kustomize apps/web-user/envs/staging | kubectl diff -f -
```

## Postgres

```bash
kubectl get cluster -n infra
kubectl get pods -n infra -l cnpg.io/cluster=postgres
kubectl exec -it -n infra postgres-1 -- psql -U postgres -d cinema -c '\du'
kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'; echo
```

## Redis

```bash
kubectl get redisreplication -n infra
kubectl get pods -n infra -L redis-role
PW=$(kubectl get secret infra-redis -n infra -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n infra redis-0 -- env REDISCLI_AUTH="$PW" redis-cli info replication
```

`REDISCLI_AUTH` thay cho `-a` để password không lộ trong danh sách tiến trình.

## Chứng chỉ và Ingress

```bash
kubectl get certificate -A
kubectl describe certificate <tên> -n cinema     # kẹt ở đâu trong quy trình ACME
kubectl get ingress -A
curl -sI https://cine.io.vn | head -3
curl -sI http://cine.io.vn | head -3             # phải thấy 301 hoặc 308
```

## Secret

```bash
kubectl get externalsecret -A                     # phải là SecretSynced
kubectl get clustersecretstore                    # phải là Valid
kubectl describe externalsecret <tên> -n <ns>
```

Không in giá trị secret ra màn hình trừ khi đang debug, và khi đó đừng dán vào chat hay issue.

## Tài nguyên máy

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
free -m
df -h
```

## Bài tập để hiểu GitOps

Làm theo thứ tự, mỗi bài vài phút. Làm trên staging.

**1. Kubernetes tự vá.** Xóa một pod web rồi xem nó tự lên lại:

```bash
kubectl delete pod -n cinema -l app.kubernetes.io/name=web-user
kubectl get pods -n cinema -w
```

Deployment giữ đúng số pod bạn khai. Đây là tầng thứ nhất.

**2. Argo CD tự vá.** Sửa cluster bằng tay, trái với Git:

```bash
kubectl scale deployment web-user -n cinema --replicas=3
kubectl get pods -n cinema -w
```

Git ghi 1, cluster thành 3, Argo CD thấy `OutOfSync` rồi `selfHeal` kéo về 1. Đây là tầng thứ hai. Hai tầng này khác nhau: Kubernetes giữ cluster đúng như bản khai trong cluster, Argo CD giữ bản khai đó đúng như Git.

**3. Đổi thật thì đổi ở Git.** Sửa `replicas` trong `apps/web-user/base/deployment.yaml`, push, rồi xem Argo CD tự sync.

**4. Prune.** Xóa một file manifest khỏi Git rồi push, xem tài nguyên tương ứng biến mất khỏi cluster. Nhớ là nó xóa thật.

**5. Đọc diff trước khi tin.** Trên UI Argo CD bấm `Diff` giữa Git và cluster; bấm `History` để xem sync trước; bấm `Manifest` để xem Argo CD render ra gì từ Helm và kustomize.

Sau 5 bài này thì ý chính đã đủ: `kubectl` dùng để xem và gỡ lỗi, còn thay đổi hệ thống thì đi qua Git.
