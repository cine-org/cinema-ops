# Tailscale

> VPS chỉ mở 22/80/443, cổng API k3s (6443) không ra Internet.

Không có Tailscale thì vào bằng SSH:

```bash
ssh cinema-prod 'kubectl get pods -A'
ssh -L 8080:localhost:8080 cinema-prod      # UI Argo CD
```

## WSL làm một máy trong mạng

### 1. Mirrored networking

`C:\Users\<user>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

```powershell
wsl --shutdown
```

### 2. systemd

`/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

```powershell
wsl --shutdown
```

Kiểm tra: `ps -p 1 -o comm=` → `systemd`.

### 3. SSH server

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

## Cài Tailscale (máy local và VPS)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip
```

```bash
ssh ops@<tailscale-ip>
```

## Để dành sau

Subnet router chạy trong cluster để gọi thẳng `postgres-rw.infra.svc` và UI Argo CD, bỏ hẳn `port-forward`. Khi đó thư mục này có thêm `base/` + `envs/` và một Application, auth key lấy từ GSM.
