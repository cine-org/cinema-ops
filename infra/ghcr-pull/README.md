# ghcr-pull

Tạo secret `ghcr-pull` ở ns `cinema` để pod kéo được image private từ `ghcr.io`.

Giá trị lấy từ GSM `cinema-ghcr-pull`: JSON gồm `username` và `token` (PAT classic, chỉ tick quyền `read:packages`). ExternalSecret dùng `target.template` đổi 2 field này sang định dạng Docker (`kubernetes.io/dockerconfigjson`):

```text
{"auths":{"ghcr.io":{"username":…,"password":<token>,"auth":base64(username:token)}}}
```

Deployment dùng secret này bằng `imagePullSecrets: [{name: ghcr-pull}]`. Secret phải nằm cùng namespace với pod.

## Phải nhớ

- Không tạo secret này bằng `kubectl create secret docker-registry`: lúc dựng lại cluster sẽ không ai biết nó từ đâu ra.
- PAT hết hạn thì pod mới báo `ImagePullBackOff`. Cách sửa: thêm version mới cho `cinema-ghcr-pull` trên GSM rồi ép ExternalSecret sync lại ([docs/gcp/gsm.md](../../docs/gcp/gsm.md), mục Đổi giá trị).

## Verify

```bash
kubectl get externalsecret ghcr-pull -n cinema                      # SecretSynced
kubectl get secret ghcr-pull -n cinema -o jsonpath='{.type}'; echo  # kubernetes.io/dockerconfigjson
```

Pod báo `ImagePullBackOff`:

- kèm `denied`: PAT sai hoặc thiếu quyền;
- kèm `manifest unknown`: tag image không tồn tại.
