# k3s

> 1 node, SQLite, giữ Traefik bundled.

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.3+k3s1 sh -
sudo k3s kubectl get nodes
```

Ghim version để lần dựng sau ra đúng cluster này.

## kubeconfig cho `ops`

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ops:ops ~/.kube/config && chmod 600 ~/.kube/config
sed -i '1i export KUBECONFIG=$HOME/.kube/config' ~/.bashrc
```

Dòng export phải ở **đầu** `.bashrc`: đoạn `case $- in *i*) ... return` của Debian chặn phần dưới khi shell không tương tác, để cuối thì `ssh cinema-prod 'kubectl ...'` báo `permission denied`. Chép lại file này sau mỗi lần k3s cấp lại cert.

## Verify

```bash
kubectl get nodes
kubectl get pods -A      # coredns, traefik, metrics-server, local-path-provisioner
```

## Thêm node sau này

Mở trong mạng riêng (VPC hoặc Tailscale), không ra Internet:

| Cổng | Dùng cho |
| --- | --- |
| `6443/tcp` | API server |
| `8472/udp` | mạng pod (flannel VXLAN) |
| `10250/tcp` | kubelet |
| `2379-2380/tcp` | etcd, chỉ khi nhiều server node |

Thiếu `8472/udp`: node `Ready` nhưng pod 2 node không nói chuyện được.

3 server node chịu được mất 1 node: thêm `--cluster-init` rồi restart k3s, k3s tự đổi SQLite sang etcd.
