# ghcr-pull

> PAT classic, chỉ tick `read:packages`. Cất ở GSM tên `cinema-ghcr-pull`: `{"username": "...", "token": "..."}`.

Không `kubectl create secret docker-registry` tay: secret tạo tay là thứ không ai biết từ đâu ra khi dựng lại cluster.

`target.template` nhào 2 field thành định dạng Docker:

```yaml
target:
  name: ghcr-pull
  template:
    type: kubernetes.io/dockerconfigjson
    data:
      .dockerconfigjson: |
        {"auths":{"ghcr.io":{"username":"{{ .username }}","password":"{{ .token }}","auth":"{{ printf "%s:%s" .username .token | b64enc }}"}}}
```

## Verify

```bash
kubectl get externalsecret ghcr-pull -n cinema                      # SecretSynced
kubectl get secret ghcr-pull -n cinema -o jsonpath='{.type}'; echo  # dockerconfigjson
```

`ImagePullBackOff` + `denied` = PAT sai hoặc thiếu quyền. `manifest unknown` = credential đúng, tag không tồn tại:

```bash
U=$(kubectl get secret ghcr-pull -n cinema -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | sed 's/.*"auth":"\([^"]*\)".*/\1/')
curl -s -H "Authorization: Bearer $(echo -n "$U" | base64 -w0)" \
  https://ghcr.io/v2/cine-org/setup-monorepo/web-user/tags/list
```

## Để dành sau

GitHub App (ESO generator `GithubAccessToken`) để token tự xoay vòng. Chưa rõ GHCR có nhận token của App cho việc pull không.
