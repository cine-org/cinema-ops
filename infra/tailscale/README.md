# Tailscale: vào cluster từ máy local

Mục tiêu: dùng `kubectl` và mở UI Argo CD từ máy của mình, mà không mở thêm cổng nào ra Internet.

Thư mục này **chưa có manifest**. Tailscale hiện chạy trên máy local và trên VPS, không phải trong cluster. Đây là ngoại lệ duy nhất của quy ước "mỗi thư mục trong `infra/` là một Application"; xem phần cuối về cách đưa nó vào cluster.

## Hiện đang vào cluster bằng gì

VPS chỉ mở 22, 80, 443. Cổng API của k3s (6443) không mở ra Internet. Vì vậy:

```bash
ssh cinema-prod 'kubectl get pods -A'          # chạy lệnh qua SSH
ssh -L 8080:localhost:8080 cinema-prod         # mở đường hầm cho UI Argo CD
```

Với UI Argo CD thì trên VPS cần `kubectl -n argocd port-forward svc/argocd-server 8080:443` chạy song song.

Tailscale thêm một lựa chọn: máy local và VPS cùng một mạng riêng, nên gọi thẳng bằng IP Tailscale, không qua Internet công cộng.

## Chuẩn bị WSL làm một máy trong mạng đó

Phần này chỉ cần nếu bạn làm việc trong WSL và muốn SSH **vào** nó, hoặc muốn nó có IP riêng trong mạng Tailscale.

### 1. Mạng kiểu mirrored

Cho WSL dùng chung network interface với Windows. File `C:\Users\<user>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

```powershell
wsl --shutdown
```

Kiểm tra trong WSL: `ip addr`, `hostname -I`.

### 2. Bật systemd

Để quản lý dịch vụ bằng `systemctl`. File `/etc/wsl.conf` trong WSL:

```ini
[boot]
systemd=true
```

```powershell
wsl --shutdown
```

Kiểm tra: `ps -p 1 -o comm=` phải in ra `systemd`.

### 3. SSH server

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo systemctl status ssh
```

## Cài Tailscale

Trên cả máy local và VPS:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip
```

Sau khi cả hai cùng đăng nhập một tài khoản, chúng thấy nhau qua IP `100.x.y.z`:

```bash
ssh ops@<tailscale-ip-của-vps>
```

Tailscale không thay thế tường lửa: 22, 80, 443 vẫn như cũ, chỉ thêm một đường riêng.

## Để dành sau: chạy trong cluster

Cách làm phổ biến là chạy một **subnet router** trong cluster: một pod Tailscale quảng bá dải IP của Service, để máy local gọi thẳng `postgres-rw.infra.svc` hay UI Argo CD mà không cần `port-forward`.

Khi làm thì thư mục này có thêm `base/` và `envs/staging/` như mọi feat khác, cộng một Application trong `clusters/staging/infra/`. Auth key lấy từ Google Secret Manager qua `ExternalSecret`, giống mọi secret khác.

Được gì: bỏ hẳn `port-forward` và đường hầm SSH; thêm node thứ hai thì vẫn vào được tất cả.
