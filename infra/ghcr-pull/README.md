# ghcr-pull: kéo image private

Mục tiêu: pod trong namespace `cinema` kéo được image private từ `ghcr.io/cine-org/...`.

## Khái niệm

Kubernetes kéo image bằng thông tin đăng nhập nằm trong một Secret kiểu `kubernetes.io/dockerconfigjson`, chính là định dạng của file `~/.docker/config.json`. Deployment chỉ tham chiếu tên Secret đó:

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull
```

Hai điều hay vấp:

- **Secret phải nằm cùng namespace với pod.** Muốn dùng ở namespace khác thì tạo thêm một cái nữa ở đó.
- Kéo image xảy ra trước khi container chạy, nên sai credential thì pod đứng ở `ImagePullBackOff`, không có log ứng dụng để xem.

## Credential

Dùng PAT classic của GitHub, chỉ tick quyền `read:packages`. Cất trong GSM tên `cinema-ghcr-pull`:

```json
{"username": "<github-user>", "token": "<PAT>"}
```

Prefix `cinema-` vì đây là credential phục vụ app, không phải hạ tầng dùng chung.

**Vì sao không tạo Secret bằng tay** (`kubectl create secret docker-registry`): một secret tạo tay là một thứ không ai biết nó từ đâu ra khi dựng lại cluster. Để trong GSM thì nó đi cùng đường với mọi secret khác, và runbook chỉ có một chỗ để nhìn.

**GitHub App** (ví dụ `cinema-release-bot`) là hướng tốt hơn về lâu dài vì token tự xoay vòng; ESO có generator `GithubAccessToken` sinh token từ private key của App. Chưa làm vì còn phải kiểm chứng GHCR có nhận token của App cho việc kéo image hay không.

## File `base/external-secret.yaml`

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ghcr-pull
  namespace: cinema
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: ghcr-pull
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"ghcr.io":{"username":"{{ .username }}","password":"{{ .token }}","auth":"{{ printf "%s:%s" .username .token | b64enc }}"}}}
  data:
    - secretKey: username
      remoteRef: {key: cinema-ghcr-pull, property: username}
    - secretKey: token
      remoteRef: {key: cinema-ghcr-pull, property: token}
```

`target.template` là chỗ ESO nhào hai field rời thành đúng định dạng Docker cần. Trường `auth` là `username:token` mã hóa base64; hàm `b64enc` có sẵn trong template của ESO.

## Verify

```bash
kubectl get externalsecret ghcr-pull -n cinema
kubectl get secret ghcr-pull -n cinema -o jsonpath='{.type}'; echo
```

Phải là `SecretSynced` và `kubernetes.io/dockerconfigjson`.

Thử thật bằng cách xem pod có kéo được image không:

```bash
kubectl get pods -n cinema
kubectl describe pod <pod> -n cinema | grep -A5 Events
```

`ImagePullBackOff` với `denied` nghĩa là PAT sai hoặc thiếu quyền `read:packages`. `manifest unknown` nghĩa là credential đúng nhưng tag không tồn tại.

Kiểm tra tag có thật trên GHCR, không cần cài `gh`, dùng chính credential trong Secret:

```bash
U=$(kubectl get secret ghcr-pull -n cinema -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | sed 's/.*"auth":"\([^"]*\)".*/\1/')
curl -s -H "Authorization: Bearer $(echo -n "$U" | base64 -w0)" \
  https://ghcr.io/v2/cine-org/setup-monorepo/web-user/tags/list
```

## Để dành sau

- Chuyển sang GitHub App để token tự xoay vòng.
- Thêm `ExternalSecret` tương tự ở namespace khác nếu có namespace mới cần kéo image private.

---

Tiếp: [chạy app](../../apps/README.md).
