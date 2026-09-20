# redis

Redis qua operator OT-Container-Kit. 1 member ở ns `infra`, không ghi đĩa.

```text
redis://:<password>@redis-master.infra.svc:6379/0
```

Chỉ giữ cache và bộ đếm rate limit — mất là dựng lại được. Lock ghế và thu hồi JWT để ở Postgres.

- [docs/setup.md](docs/setup.md) · [docs/ha.md](docs/ha.md) · [docs/cheatsheet.md](docs/cheatsheet.md)
