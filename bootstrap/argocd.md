# 2. Argo CD và root application

Mục tiêu: cài Argo CD, cho nó quyền đọc repo này, rồi apply một Application duy nhất tên `root-staging`. Từ lúc đó mọi thứ khác vào cluster bằng `git push`.

## Khái niệm

**Argo CD** so hai thứ với nhau: bản khai trong Git và trạng thái thật trên cluster. Lệch thì nó gọi là `OutOfSync`, và nếu bật `automated` thì nó tự apply cho khớp.

**Application** là một CRD của Argo CD, trả lời: lấy manifest từ đâu (repo, đường dẫn hoặc chart), apply vào cluster nào, namespace nào, có tự sync không.

**App-of-apps** là mẹo: một Application trỏ vào một thư mục chứa toàn file Application khác. Argo CD apply các file đó, mỗi file thành một Application, rồi từng cái tự sync tiếp. Ở repo này Application gốc tên `root-staging`, trỏ vào `clusters/staging/`.

Một điểm dễ vấp: `root-staging` quản lý mọi Application trong `clusters/staging/`, nhưng **bản thân nó nằm ngoài thư mục đó**, ở `bootstrap/argocd/`. Nghĩa là nó không tự quản lý chính nó. Mỗi lần sửa `root-application.yaml` (đổi `path`, thêm `directory.recurse`) đều phải `kubectl apply` lại bằng tay; push Git thôi không đủ.

## 1. Cài Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## 2. Cài Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head
```

Lấy version mới nhất ở danh sách trên rồi điền vào `--version`. Repo này cần được clone về VPS để dùng hai file values, hoặc bạn chép nội dung chúng sang:

```bash
helm install argocd argo/argo-cd \
  --version 10.4.0 \
  -n argocd --create-namespace \
  -f bootstrap/argocd/common-values.yaml \
  -f bootstrap/argocd/staging/values.yaml
```

Hai file values tắt những phần chưa dùng (HA Redis, Dex, notifications) và hạ `resources` xuống cho vừa VPS nhỏ. `common-values.yaml` dùng chung mọi môi trường, `staging/values.yaml` là phần riêng của staging và hiện đang trống.

```bash
kubectl get pods -n argocd
```

## 3. Cho Argo CD quyền đọc repo

Repo `cinema-ops` là private nên phải khai credential. Tạo fine-grained PAT: GitHub → Settings → Developer settings → Fine-grained tokens → New token. Resource owner `cine-org`, chỉ chọn repo `cinema-ops`, quyền `Contents: Read-only`.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cinema-ops-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/cine-org/cinema-ops.git
  username: x-access-token
  password: <PAT>
EOF
```

Nhãn `argocd.argoproj.io/secret-type: repository` là thứ khiến Argo CD nhận ra Secret này; thiếu nhãn thì nó chỉ là một Secret bình thường và Argo CD báo không clone được repo.

GitHub App `argocd-cinema-ops-reader` đã tạo sẵn trong `cine-org`, dùng thay PAT sau này thì token tự xoay vòng.

## 4. Apply root application

File `bootstrap/argocd/staging/root-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-staging
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/cine-org/cinema-ops.git
    targetRevision: main
    path: clusters/staging
    directory:
      recurse: true

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

`directory.recurse: true` để Argo CD quét cả thư mục con `clusters/staging/infra/`. Thiếu nó thì các Application trong thư mục con bị bỏ qua, im lặng, không báo lỗi.

Apply, một lần:

```bash
kubectl apply -f bootstrap/argocd/staging/root-application.yaml
```

Hoặc dán thẳng nội dung trên vào `kubectl apply -f -` nếu chưa clone repo về VPS.

## 5. Xem UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Từ máy local:

```bash
ssh -L 8080:localhost:8080 cinema-prod
```

Mở `https://localhost:8080`, đăng nhập `admin` với password ở trên. Argo CD không mở ra Internet: cổng 6443 và UI đều chỉ vào được qua SSH hoặc Tailscale.

## Verify

```bash
kubectl get app -n argocd
```

`root-staging` phải `Synced` và `Healthy`, kéo theo các Application con trong `clusters/staging/`. Lần sync đầu tiên có thể vài cái đỏ một nhịp, vì Application dùng CRD của Application khác chưa cài xong; `retry` sẽ tự chạy lại.

## Từ đây trở đi

```text
sửa file → git push → Argo CD tự apply (chậm nhất khoảng 3 phút)
```

Chưa cấu hình webhook nên Argo CD hỏi Git theo chu kỳ. Muốn nhanh hơn thì ép nó đọc lại:

```bash
kubectl annotate app root-staging -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

SSH vào VPS chỉ để xem và gỡ lỗi, không để sửa trạng thái cluster.

---

Tiếp: [namespace](../infra/namespaces/README.md).
