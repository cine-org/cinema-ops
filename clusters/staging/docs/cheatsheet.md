# Cheatsheet

```bash
kubectl get nodes
kubectl get pods -A
kubectl get app -n argocd
```

## Argo CD

```bash
kubectl describe app <tên> -n argocd                        # lý do OutOfSync
kubectl annotate app <tên> -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd port-forward svc/argocd-server 8080:443   # + ssh -L 8080:localhost:8080
```

## Debug pod

```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> -f
kubectl logs <pod> -n <ns> --previous
kubectl get events -n <ns> --sort-by=.lastTimestamp
```

## Trước khi push

```bash
kubectl kustomize infra/postgres/envs/staging
kubectl kustomize apps/web-user/envs/staging | kubectl diff -f -
```

## Tài nguyên

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

## Thử 2 tầng tự vá

```bash
kubectl delete pod -n cinema -l app.kubernetes.io/name=web-user   # Deployment dựng lại
kubectl scale deployment web-user -n cinema --replicas=3          # Argo CD selfHeal về 1
```
