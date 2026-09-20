# k3s

> Cài k3s 1 node. Không disable Traefik.

## Cài

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.3+k3s1 sh -
sudo systemctl status k3s
sudo k3s kubectl get nodes
```

Ghim version để lần dựng sau ra đúng cluster này. Datastore là SQLite — nhẹ nhất cho 1 node.

## kubeconfig cho `ops`

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ops:ops ~/.kube/config
chmod 600 ~/.kube/config
sed -i '1i export KUBECONFIG=$HOME/.kube/config' ~/.bashrc
```

Dòng export phải ở **đầu** `~/.bashrc`: đoạn `case $- in *i*) ... return` của Debian chặn mọi thứ phía dưới khi shell không tương tác, nên đặt ở cuối thì `ssh cinema-prod 'kubectl get pods'` báo `permission denied`.

k3s cấp lại cert sau upgrade thì chép lại file này.

## Verify

```bash
kubectl get nodes
kubectl get pods -A     # coredns, traefik, metrics-server, local-path-provisioner
```

## Thêm node sau này

Chỉ mở trong mạng riêng (VPC hoặc Tailscale):

| Cổng | Dùng cho |
| --- | --- |
| `6443/tcp` | API server |
| `8472/udp` | mạng pod giữa node (flannel VXLAN) |
| `10250/tcp` | kubelet: log, exec, metrics |
| `2379-2380/tcp` | etcd, chỉ khi nhiều server node |

```bash
sudo ufw allow from <subnet> to any port 6443,10250 proto tcp
sudo ufw allow from <subnet> to any port 8472 proto udp
```

Thiếu `8472/udp` là bẫy khó thấy nhất: node `Ready` nhưng pod 2 node không nói chuyện được.

Control plane chịu được mất 1 node cần 3 server node dùng etcd — thêm `--cluster-init` rồi restart k3s một lần, k3s tự đổi SQLite sang etcd.
