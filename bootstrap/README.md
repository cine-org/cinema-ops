# 1. VPS và k3s

Mục tiêu: từ một VPS trống thành một cluster k3s một node, chạy được `kubectl`. Chưa cài Argo CD, chưa có app nào.

Đây là phần duy nhất làm bằng tay. Từ sau khi Argo CD chạy, mọi thứ khác đi qua Git.

## 1. Đăng nhập lần đầu và cập nhật

```bash
ssh root@<VPS_IP>
```

```bash
sudo apt update && sudo apt upgrade -y
```

Xem qua tình trạng máy:

```bash
uname -r; uptime; df -h; free -m
```

## 2. Tạo user `ops`

Không chạy dịch vụ bằng `root`.

```bash
sudo adduser ops
sudo usermod -aG sudo ops
```

Sinh password mạnh khi được hỏi:

```bash
openssl rand -hex 24
```

## 3. Khóa SSH

Trên **máy local**:

```bash
ssh-keygen -t ed25519 -C "ops-key"
```

Khóa riêng (`id_ed25519`) không bao giờ rời máy bạn, chỉ khóa công khai (`id_ed25519.pub`) được đưa lên VPS.

Thêm vào `~/.ssh/config` của máy local cho đỡ gõ:

```text
Host cinema-prod
    HostName <VPS_IP>
    User ops
    IdentityFile ~/.ssh/id_ed25519
```

Trên **VPS**, dán nội dung file `.pub` vào:

```bash
mkdir -p /home/ops/.ssh
nano /home/ops/.ssh/authorized_keys
chown -R ops:ops /home/ops/.ssh
chmod 700 /home/ops/.ssh
chmod 600 /home/ops/.ssh/authorized_keys
```

Sai quyền thì đăng nhập bằng khóa hỏng mà không báo lỗi gì. Thử đăng nhập trước khi đi tiếp:

```bash
ssh cinema-prod
```

## 4. Siết SSH

Sửa `/etc/ssh/sshd_config`:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

```bash
sudo systemctl restart ssh
```

Phải chắc chắn bước 3 đăng nhập được **trước khi** tắt password, không thì tự khóa mình ở ngoài.

## 5. Tường lửa

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22    # SSH
sudo ufw allow 80    # HTTP, Traefik
sudo ufw allow 443   # HTTPS, Traefik

sudo ufw enable
sudo ufw status
```

Cổng `6443` (API server) **không** mở ra Internet. Cần `kubectl` từ ngoài thì đi qua SSH hoặc Tailscale, xem [infra/tailscale/README.md](../infra/tailscale/README.md).

Nhà cung cấp VPS có tường lửa riêng ở tầng của họ thì đặt cùng bộ luật đó.

## 6. Fail2ban và vài công cụ

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo apt install -y git curl wget unzip htop
```

Không cài `nginx` (Traefik đi kèm k3s đã làm việc đó) và không cài `docker` (k3s dùng containerd sẵn bên trong).

## 7. Swap

VPS nhỏ nên cần swap để một lúc cao điểm không giết tiến trình.

```bash
sudo fallocate -l 2G /swapfile     # máy nào fallocate lỗi thì:
                                   # sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
sudo sysctl vm.vfs_cache_pressure=50
```

Không ghi vào `/etc/fstab` thì reboot là mất:

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 8. Cài k3s

Ghim cứng version, để lần dựng sau ra đúng cluster như lần này:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.3+k3s1 sh -
```

Không tắt Traefik: cả hệ thống này dùng bản Traefik đi kèm k3s.

Cài như trên là một server node, dữ liệu cluster nằm trong SQLite — nhẹ nhất cho một node.

```bash
sudo systemctl status k3s
sudo k3s kubectl get nodes
```

## 9. kubeconfig cho user `ops`

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ops:ops ~/.kube/config
chmod 600 ~/.kube/config
```

`kubectl` của k3s mặc định đọc `/etc/rancher/k3s/k3s.yaml`, mà file đó chỉ `root` đọc được. Phải trỏ nó sang bản vừa chép, và đặt dòng này ở **đầu** `~/.bashrc`:

```bash
sed -i '1i export KUBECONFIG=$HOME/.kube/config' ~/.bashrc
```

Vì sao phải ở đầu file: `~/.bashrc` của Debian có đoạn `case $- in *i*) ... return` chặn mọi thứ phía dưới khi shell không tương tác. Đặt ở cuối thì `ssh cinema-prod 'kubectl get pods'` vẫn báo `permission denied`, trong khi đăng nhập rồi gõ tay lại chạy.

Sau khi k3s cấp lại chứng chỉ (thường là sau upgrade) thì chép lại file này.

Kiểm tra:

```bash
kubectl get nodes
kubectl get pods -A
```

Phải thấy node `Ready` và các pod của k3s: `coredns`, `traefik`, `metrics-server`, `local-path-provisioner`.

## Xử lý sự cố

**Không phân giải được tên miền GitHub.** Sửa `/etc/resolv.conf`:

```text
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 8.8.8.8
```

**Cần `git clone` tay trên VPS để gỡ lỗi.** Argo CD có credential riêng của nó, không dùng git của máy. Nếu vẫn cần thì dùng PAT qua HTTPS:

```bash
git clone https://<PAT>@github.com/cine-org/cinema-ops.git
```

PAT dùng kéo image (`read:packages`) không clone được repo private; cần PAT khác có quyền `Contents: read`.

## Thêm node về sau

Hiện chạy một node vì chi phí. Khi thêm node thì các node phải thấy nhau qua những cổng dưới đây. Chỉ mở trong mạng riêng (VPC của nhà cung cấp hoặc Tailscale), không mở ra Internet:

| Cổng | Dùng cho |
| --- | --- |
| `6443/tcp` | node khác gọi API server |
| `8472/udp` | mạng pod giữa các node (flannel VXLAN) |
| `10250/tcp` | kubelet: log, exec, metrics |
| `2379-2380/tcp` | etcd giữa các server node, chỉ khi có nhiều server |

```bash
sudo ufw allow from <subnet-riêng> to any port 6443,10250 proto tcp
sudo ufw allow from <subnet-riêng> to any port 8472 proto udp
```

Thiếu `8472/udp` là cái bẫy khó thấy nhất: node vẫn `Ready`, nhưng pod ở hai node không nói chuyện được với nhau.

Muốn control plane chịu được mất một node thì cần ba server node dùng etcd. Chuyển tại chỗ bằng cách thêm `--cluster-init` rồi restart k3s một lần; k3s tự đổi SQLite sang etcd, pod vẫn chạy, API gián đoạn trong chốc lát:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.3+k3s1 sh -s - server --cluster-init
```

Không bật sẵn từ đầu: etcd tốn RAM và ghi đĩa nhiều hơn, mà một node thì không được lợi gì.

---

Tiếp: [cài Argo CD](argocd.md).
