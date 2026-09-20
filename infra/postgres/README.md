# postgres

Postgres qua operator CloudNativePG. 1 instance ở ns `infra`, database `cinema`, 3 role: `cinema` (owner, migration), `cinema_rw`, `cinema_ro`.

```text
postgresql://cinema_rw:<pw>@postgres-rw.infra.svc:5432/cinema
```

| Service | Dùng cho |
| --- | --- |
| `postgres-rw` | đọc + ghi, primary |
| `postgres-ro` | chỉ đọc, chỉ replica |
| `postgres-r` | chỉ đọc, mọi instance |

- [docs/setup.md](docs/setup.md) · [docs/cheatsheet.md](docs/cheatsheet.md)
