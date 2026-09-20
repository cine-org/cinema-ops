# cert-manager

Xin và tự gia hạn chứng chỉ TLS. 2 `ClusterIssuer`: `letsencrypt-staging` (thử) và `letsencrypt-prod` (thật).

Dùng ở Ingress bằng annotation `cert-manager.io/cluster-issuer`, không viết `Certificate` tay.

- [docs/setup.md](docs/setup.md)
