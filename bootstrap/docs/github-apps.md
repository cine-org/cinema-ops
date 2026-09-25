# GitHub Apps

> 2 App của org `cine-org`, đều cài vào `cinema-ops` (repository access: only selected). Private key cất ở GSM.

| App                        | App ID  | Installation ID | Dùng bởi                                          | Quyền                                              |
| -------------------------- | ------- | --------------- | ------------------------------------------------- | -------------------------------------------------- |
| `cinema-release-bot`       | 4625326 | 154423355       | CI repo `cinema`: mở/merge PR đổi tag, đọc status | Contents RW · Pull requests RW · Commit statuses R |
| `argocd-cinema-ops-reader` | 4630807 | 154539301       | Argo CD: đọc repo, ghi status sau sync            | Contents R · Commit statuses RW                    |

Metadata R là quyền bắt buộc, GitHub tự thêm.

Installation ID nằm cuối URL ở cine-org → Settings → GitHub Apps → Configure, hoặc:

```bash
gh api orgs/cine-org/installations --jq '.installations[] | "\(.app_slug) \(.id)"'
```

Key của `cinema-release-bot` nằm ở secret `RELEASE_BOT_PRIVATE_KEY` của repo `cinema`, không vào cluster.
