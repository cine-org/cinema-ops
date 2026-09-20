# VPS

> VPS trống → sẵn sàng cài k3s.

## 1. Update + user

```bash
sudo apt update && sudo apt upgrade -y
sudo adduser ops            # password: openssl rand -hex 24
sudo usermod -aG sudo ops
```

## 2. Khóa SSH

Máy local:

```bash
ssh-keygen -t ed25519 -C "ops-key"
```

`~/.ssh/config`:

```text
Host cinema-prod
    HostName <VPS_IP>
    User ops
    IdentityFile ~/.ssh/id_ed25519
```

VPS — dán nội dung `.pub` vào `authorized_keys`:

```bash
mkdir -p /home/ops/.ssh
nano /home/ops/.ssh/authorized_keys
chown -R ops:ops /home/ops/.ssh
chmod 700 /home/ops/.ssh
chmod 600 /home/ops/.ssh/authorized_keys
```

Sai quyền là hỏng login mà không báo lỗi. Thử `ssh cinema-prod` trước khi sang bước 3.

## 3. Siết SSH

`/etc/ssh/sshd_config` → `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`.

```bash
sudo systemctl restart ssh
```

## 4. Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22 && sudo ufw allow 80 && sudo ufw allow 443
sudo ufw enable
```

6443 (API k3s) không mở — vào qua SSH hoặc Tailscale.

## 5. Fail2ban + tools

```bash
sudo apt install -y fail2ban git curl wget unzip htop
sudo systemctl enable --now fail2ban
```

Không cài nginx (đã có Traefik) và docker (k3s dùng containerd).

## 6. Swap 2G

```bash
sudo fallocate -l 2G /swapfile     # lỗi thì: dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
sudo sysctl vm.vfs_cache_pressure=50
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Sự cố

- DNS không ra GitHub → thêm `nameserver 1.1.1.1` vào `/etc/resolv.conf`.
- Clone repo private tay: `git clone https://<PAT>@github.com/...` (PAT `read:packages` không clone được).
