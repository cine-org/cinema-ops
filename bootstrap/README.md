# bootstrap

Phần chạy tay, một lần, trước khi Argo CD tồn tại. Chứa values Helm của Argo CD và `root-application.yaml`.

`root-application.yaml` không tự quản lý chính nó: sửa file này thì phải `kubectl apply` lại tay.

- [docs/vps.md](docs/vps.md) — user, SSH, firewall, swap
- [docs/k3s.md](docs/k3s.md) — cài k3s, kubeconfig
- [docs/github-apps.md](docs/github-apps.md) — 2 GitHub App, quyền, ID
- [docs/argocd.md](docs/argocd.md) — cài Argo CD, credential repo, root app
