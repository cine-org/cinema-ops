# bootstrap

Mọi việc làm tay khi dựng một env mới trên VPS trống. Xong mục 3 (Argo CD + root app), mọi thứ khác vào cluster bằng `git push`.

| Env     | SSH alias        | Domain                 |
| ------- | ---------------- | ---------------------- |
| staging | `cinema-staging` | `*.staging.cine.io.vn` |

## Chuẩn bị

GCP, mỗi env một project:

- VM: [docs/gcp/gce.md](../docs/gcp/gce.md).
- GSM: [docs/gcp/gsm.md](../docs/gcp/gsm.md).

Coi repo là private: Argo CD đọc repo bằng GitHub App `argocd-cinema-ops-reader` (App ID `4630807`, Installation ID `154539301`, quyền Contents R · Commit statuses RW).

Mỗi env một private key: GitHub → cine-org → Settings → GitHub Apps → `argocd-cinema-ops-reader` → Private keys → Generate. Lưu thành file `infra-argocd-github-app.pem`.

File secret giữ ở máy local, không commit và không để trên VPS. File đưa lên GSM đặt tên theo tên secret. Các lệnh bên dưới chỉ ghi tên file.

Mỗi phiên terminal ở máy local, đứng ở thư mục repo, khai env một lần; các lệnh bên dưới dùng lại:

```bash
ENV=staging              # envs/<env>, bootstrap/root/<env>.yaml
HOST=cinema-$ENV         # SSH alias
```

Lệnh chạy ở đâu:

- **Mặc định: trên VPS**, trong phiên `ssh $HOST`. Phần lớn các bước cần `sudo` gõ password.
- **Máy local**, trong thư mục repo: chỉ các lệnh cần file của repo hoặc key (đánh dấu _máy local_). File đi qua stdin dạng `ssh "$HOST" '…' < file`, nên không clone repo lên VPS và key không nằm lại trên VPS.

```text
VPS trống ─▶ 1. VPS ─▶ 2. k3s ─▶ 3. Argo CD (helm install tay 1 lần, apply root app)
                                   └─▶ Argo CD tự quản lý chính nó + mọi thứ trong infra/, apps/
```

---

# 1. VPS

## 1.1 Update + user

```bash
sudo apt update && sudo apt upgrade -y
sudo adduser ops            # password: openssl rand -hex 24
sudo usermod -aG sudo ops
```

## 1.2 Khoá SSH

Máy local:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/cinema/${ENV}_key -C "ops@$ENV"
```

`~/.ssh/config`:

```text
Host cinema-<env>
    HostName <VPS_IP>
    User ops
    IdentityFile ~/.ssh/cinema/<env>_key
```

VPS: dán nội dung `.pub` vào `authorized_keys`.

```bash
mkdir -p /home/ops/.ssh
nano /home/ops/.ssh/authorized_keys
chown -R ops:ops /home/ops/.ssh
chmod 700 /home/ops/.ssh
chmod 600 /home/ops/.ssh/authorized_keys
```

Sai quyền là hỏng login mà không báo lỗi. Thử `ssh "$HOST"` trước khi siết SSH.

## 1.3 Siết SSH

```bash
nano /etc/ssh/sshd_config
```

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

```bash
sudo systemctl restart ssh
```

Giữ phiên SSH cũ mở và thử đăng nhập ở cửa sổ khác trước khi thoát.

## 1.4 Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22 && sudo ufw allow 80 && sudo ufw allow 443
sudo ufw enable
```

Không mở 6443 (API k3s): `kubectl` chạy trên VPS qua SSH. Nhà cung cấp cloud có firewall riêng thì mở 22/80/443 ở cả đó.

## 1.5 Fail2ban + tools

```bash
sudo apt install -y fail2ban git curl unzip htop
sudo systemctl enable --now fail2ban
```

Không cài nginx (k3s có Traefik) và docker (k3s dùng containerd).

## 1.6 Swap 2G

```bash
sudo fallocate -l 2G /swapfile     # lỗi thì: sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Verify

```bash
sudo ufw status               # active, 22/80/443 ALLOW
systemctl is-active fail2ban  # active
sudo swapon --show            # /swapfile 2G
```

DNS trong VPS không ra GitHub thì thêm `nameserver 1.1.1.1` vào `/etc/resolv.conf`.

---

# 2. k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.3+k3s1 sh -
sudo k3s kubectl get nodes
```

Ghim version để lần dựng sau ra đúng cluster này. k3s cài sẵn Traefik (ingress), local-path (StorageClass), CoreDNS, metrics-server.

## kubeconfig cho `ops`

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ops:ops ~/.kube/config && chmod 600 ~/.kube/config
sed -i '1i export KUBECONFIG=$HOME/.kube/config' ~/.bashrc
source ~/.bashrc
```

Dòng export phải ở **đầu** `.bashrc`: đoạn `case $- in *i*) ... return` của Debian/Ubuntu dừng file sớm khi shell không tương tác, để cuối thì các lệnh _máy local_ ở mục 3 (`ssh "$HOST" 'kubectl …'`) báo `permission denied`. Chép lại file sau mỗi lần k3s cấp lại cert.

## Verify

```bash
kubectl get nodes          # Ready
kubectl get pods -A        # coredns, traefik, metrics-server, local-path-provisioner Running
```

## Thêm node sau này

Mở trong mạng riêng (VPC), không ra Internet:

| Cổng            | Dùng cho                        |
| --------------- | ------------------------------- |
| `6443/tcp`      | API server                      |
| `8472/udp`      | mạng pod (flannel VXLAN)        |
| `10250/tcp`     | kubelet                         |
| `2379-2380/tcp` | etcd, chỉ khi nhiều server node |

Thiếu `8472/udp` thì node `Ready` nhưng pod ở 2 node không nói chuyện được.

---

# 3. Argo CD

```text
helm install (tay, 1 lần) ─▶ Argo CD chạy
kubectl apply root app    ─▶ Argo CD nhận quản lý chính release đó
                             + ApplicationSet infra, apps ─▶ 1 Application / thư mục envs/<env>
```

Code phải đã merge vào `main` trên GitHub: Argo CD đọc GitHub, không đọc máy local.

## 3.1 Cài helm (trên VPS)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
```

## 3.2 Cài Argo CD

_Máy local._

```bash
ssh "$HOST" 'helm install argocd argo/argo-cd --version 10.4.0 -n argocd --create-namespace -f -' < infra/argocd/values.yaml
```

Chỉ cài tay lần đầu. Tên release (`argocd`) và version phải trùng `bootstrap/root/<env>.yaml`, để ở bước root app, Argo CD nhận quản lý đúng release này. Từ đó sửa `infra/argocd/values.yaml` rồi push, không `helm upgrade` nữa.

## 3.3 Secret tạo tay

Mọi secret đi qua GSM + External Secrets, trừ những secret cần có **trước** khi GitOps chạy được. Chỉ những secret trong bảng này được tạo tay, và phải tạo trước root app:

| Secret              | Ns       | Vì sao phải tạo tay                                           |
| ------------------- | -------- | ------------------------------------------------------------- |
| `cinema-ops-repo`   | `argocd` | Argo CD cần nó để đọc repo, trước khi cài được gì             |
| `gcpsm-credentials` | `infra`  | External Secrets cần nó để đọc GSM, nên không lấy từ GSM được |

_Máy local._ Key đi qua stdin:

```bash
ssh "$HOST" 'kubectl create secret generic cinema-ops-repo -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/cine-org/cinema-ops.git \
  --from-literal=githubAppID=4630807 \
  --from-literal=githubAppInstallationID=154539301 \
  --from-file=githubAppPrivateKey=/dev/stdin \
  && kubectl label secret cinema-ops-repo -n argocd argocd.argoproj.io/secret-type=repository' \
  < infra-argocd-github-app.pem

ssh "$HOST" 'kubectl create ns infra --dry-run=client -o yaml | kubectl apply -f - \
  && kubectl create secret generic gcpsm-credentials -n infra \
  --from-file=secret-access-credentials=/dev/stdin' < gcpsm-credentials.json
```

- `url` phải khớp từng ký tự với `repoURL` trong root app và ApplicationSet. Thiếu label `argocd.argoproj.io/secret-type=repository` thì Argo CD không thấy credential.
- Namespace `infra` về sau do Argo CD quản lý; tạo trước ở đây chỉ để chứa key.
- Sau bootstrap, secret nào có ExternalSecret đi kèm thì đổi giá trị ở GSM, không tạo tay lại (xem README của từng thư mục `infra/<feat>/`).

## 3.4 Root app

Trước bước này, code phải đã **merge vào `main`** (push lên branch chưa đủ): root app và 2 ApplicationSet đọc `targetRevision: main` trên GitHub, thiếu `infra/argocd/envs/<env>` thì Argo CD báo `path does not exist`.

_Máy local._

```bash
ssh "$HOST" 'kubectl apply -f -' < "bootstrap/root/$ENV.yaml"
```

Root không tự quản lý file của chính nó: sửa `bootstrap/root/<env>.yaml` thì apply lại lệnh trên.

## Verify

```bash
kubectl get app,applicationset -n argocd     # mọi app Synced/Healthy; appset infra, apps
```

Từng thành phần có mục Verify riêng trong `infra/<feat>/README.md`.

Credential đọc repo: trên **UI của Argo CD** (mục UI bên dưới), Settings → Repositories → dòng `cinema-ops` báo `Successful`.

## UI

UI không mở ra Internet (Ingress chỉ mở path webhook); vào qua SSH tunnel:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

_Máy local_, mở tunnel:

```bash
ssh -L 8080:localhost:8080 "$HOST" kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Mở `http://localhost:8080`, user `admin`. Đăng nhập xong nên đổi password (User Info → Update Password) rồi xoá secret `argocd-initial-admin-secret`.

## Sự cố

Commit values hỏng làm Argo CD không lên được để tự sửa: chạy lại lệnh cài Argo CD với `helm upgrade --install` và values đã sửa, rồi push bản sửa.
