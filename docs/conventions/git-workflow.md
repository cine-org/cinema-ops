# Git workflow

Repo chỉ có `main`. Mọi thay đổi vào `main` qua PR, merge **squash**, check bắt buộc là `ci` (`.github/scripts/validate.sh`).

## PR

| Loại              | Nhánh                       | Ai mở                | Ai merge            |
| ----------------- | --------------------------- | -------------------- | ------------------- |
| Deploy staging    | `promote/staging-sha-<7>`   | `cinema-release-bot` | bot tự merge        |
| Deploy production | `promote/production-vX.Y.Z` | `cinema-release-bot` | owner duyệt + merge |
| Hạ tầng, cấu hình | `<type>/<issue>/<summary>`  | người                | người               |

- File `envs/production/` cần team `@cine-org/ops` duyệt (`CODEOWNERS`); staging thì không.
- Owner tự mở PR đụng production thì không tự duyệt được: merge bằng bypass admin (vẫn phải qua PR và `ci`).
- PR hạ tầng/cấu hình mà code `cinema` cần tới phải merge **trước** PR `scope → main` bên đó, và phải tương thích ngược với image đang chạy.

## Commit / PR title

Conventional Commits, giống repo `cinema`. Title PR là commit trên `main`.

```text
<type>(<scope>): <summary>
```

- **type**: `feat` thêm mới, `fix` sửa/rollback, `chore` deploy và bảo trì, `refactor`, `docs`, `ci`, `revert`.
- **scope**:
  - deploy: tên env (`staging`, `production`);
  - còn lại: tên thư mục feature (`rabbitmq`, `argocd`, `api`); đụng nhiều feature thì bỏ scope.
- Chỉ đụng một env thì ghi env ở cuối summary.

```text
chore(staging): deploy sha-f9e8d7c (#14)          ← bot
chore(production): deploy v0.1.0 (#15)            ← bot
feat(rabbitmq): add RabbitMQ on staging (#12)
feat(worker): add worker app on staging (#11)
feat(api): add OAuth client secret and env (#13)
fix(production): roll back api to v0.1.0 (#18)
```

## Deploy

- Đổi version = đổi `newTag` trong `apps/<app>/envs/<env>/kustomization.yaml`. Không sửa gì khác trong PR deploy.
- Tag: staging `sha-<7>`, production `vX.Y.Z`. Không dùng `latest`.
- Không `kubectl apply` / `edit` vào cluster; Argo CD sync từ `main`.
- Rollback: PR đặt lại `newTag` cũ cho đúng app cần lùi, không `git revert` cả commit deploy.

## Issue

Title `[Ops] <Type>: <summary>`. Mỗi issue là 1 khối feature (VD "Staging"), không tách theo file.
Việc lặp lại (thêm infra, thêm app, thêm config) là quy trình trong README, không mở issue riêng.
