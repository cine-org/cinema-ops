# Argo CD

> Xong bước này, mọi thứ khác vào cluster bằng `git push`.

## 1. Cài

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd --version 10.4.0 \
  -n argocd --create-namespace \
  -f bootstrap/argocd/common-values.yaml \
  -f bootstrap/argocd/staging/values.yaml
```

Values tắt HA Redis, Dex, notifications và hạ resources cho vừa VPS nhỏ.

## 2. Credential đọc repo

Fine-grained PAT: owner `cine-org`, repo `cinema-ops`, `Contents: Read-only`.

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: cinema-ops-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/cine-org/cinema-ops.git
  username: x-access-token
  password: <PAT>
YAML
```

Thiếu label `secret-type: repository` thì Argo CD không thấy credential.

## 3. Root application

```bash
kubectl apply -f bootstrap/argocd/staging/root-application.yaml
```

`directory.recurse: true` để quét cả `clusters/staging/infra/`; thiếu nó thì Application trong thư mục con bị bỏ qua, im lặng.

## 4. UI

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Máy local: `ssh -L 8080:localhost:8080 cinema-prod` → `https://localhost:8080`.

## Verify

```bash
kubectl get app -n argocd
```

`root-staging` `Synced/Healthy`. Lần đầu vài Application đỏ một nhịp vì chờ CRD, `retry` tự chạy lại.
