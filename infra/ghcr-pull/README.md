# ghcr-pull

Secret `kubernetes.io/dockerconfigjson` ở ns `cinema` để pod kéo image private từ `ghcr.io`. ESO dựng từ PAT trong GSM (`cinema-ghcr-pull`).

Deployment dùng bằng `imagePullSecrets: [{name: ghcr-pull}]`. Secret phải cùng namespace với pod.

- [docs/setup.md](docs/setup.md)
