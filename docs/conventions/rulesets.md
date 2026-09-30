# Rulesets

Cấu hình GitHub bảo vệ `main` của repo này. Nguồn thật là **Settings → Rules → Rulesets** trên GitHub. Trang này mô tả từng ruleset: dựng lại repo thì cấu hình theo các bảng dưới, đổi ruleset thì sửa trang này qua PR.

Chỉ có `main`. Người sửa qua nhánh ngắn + PR; bot mở PR deploy (staging tự merge, production người merge). Quy ước PR/commit: [git-workflow.md](git-workflow.md).

## Repo settings (Settings → General)

| Setting                            | Chọn                      |
| ---------------------------------- | ------------------------- |
| Allow squash merging               | ✅, title = PR title      |
| Allow merge commits / rebase       | ❌                        |
| Allow auto-merge                   | ✅ (bot dùng cho staging) |
| Automatically delete head branches | ✅                        |

## `main`

Chỉ bật các rule dưới đây, còn lại tắt.

| Rule                              | Chọn                         | Ghi chú                                                      |
| --------------------------------- | ---------------------------- | ------------------------------------------------------------ |
| Bypass list                       | Repository admin, chỉ qua PR | Bot không bypass. Admin vẫn qua PR + `ci`, chỉ bỏ bước duyệt |
| Restrict deletions                | ✅                           |                                                              |
| Block force pushes                | ✅                           |                                                              |
| Require pull request              | ✅                           |                                                              |
| ↳ Required approvals              | 0                            | PR staging của bot tự merge được                             |
| ↳ Require review from Code Owners | ✅                           | Chỉ PR đụng file production mới cần duyệt                    |
| ↳ Conversation resolution         | ✅                           |                                                              |
| ↳ Allowed merge methods           | squash                       |                                                              |
| Required status checks            | `ci`                         | `ci.yml`: kustomize build + kubeconform                      |

`.github/CODEOWNERS` giao file production cho team `@cine-org/ops` (team phải có quyền write vào repo):

```text
/apps/*/envs/production/         @cine-org/ops
/infra/*/envs/production/        @cine-org/ops
/bootstrap/root/production.yaml  @cine-org/ops
```

Kết quả:

- PR staging của bot chỉ sửa `envs/staging/`: không cần duyệt, auto-merge khi `ci` xanh.
- PR production do bot mở: owner duyệt rồi merge (owner không phải tác giả nên duyệt được).
- PR owner tự mở mà đụng file production: không tự duyệt được, merge bằng bypass admin.

## GitHub Apps

| App                        | Cài vào                | Quyền                                              | Dùng cho                                                           |
| -------------------------- | ---------------------- | -------------------------------------------------- | ------------------------------------------------------------------ |
| `cinema-release-bot`       | `cinema-ops`, `cinema` | Contents RW · Pull requests RW · Commit statuses R | CI repo `cinema`: mở PR deploy sang đây, tạo tag `v*` bên `cinema` |
| `argocd-cinema-ops-reader` | `cinema-ops`           | Contents R · Commit statuses RW                    | Argo CD đọc repo, ghi commit status sau sync                       |

Key của `cinema-release-bot` nằm ở secret `RELEASE_BOT_PRIVATE_KEY` của repo `cinema`, không vào cluster. Key của `argocd-cinema-ops-reader` nằm ở GSM, mỗi env một key.
