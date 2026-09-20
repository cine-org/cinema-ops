# external-secrets

Đồng bộ secret từ Google Secret Manager (GSM) vào cluster. Git chỉ chứa công thức (`ExternalSecret`), không chứa giá trị.

```text
GSM  →  ESO  →  Secret K8s  →  Postgres / Redis / app
```

- [docs/setup.md](docs/setup.md)
