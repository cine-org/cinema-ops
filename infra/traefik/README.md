# traefik

Đường vào từ Internet. Traefik đi kèm k3s, thư mục này chỉ đè cấu hình bằng `HelmChartConfig`: chuyển mọi HTTP sang HTTPS.

```text
trình duyệt → DNS Cloudflare (DNS only) → :443 VPS → Traefik (cắt TLS) → Service → Pod
```

- [docs/setup.md](docs/setup.md)
