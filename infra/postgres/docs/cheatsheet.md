# Postgres cheatsheet

```bash
kubectl get cluster,pods -n infra -l cnpg.io/cluster=postgres
kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'; echo
kubectl exec -it -n infra postgres-1 -- psql -U postgres -d cinema
kubectl cnpg status postgres -n infra          # nếu có plugin cnpg
```

Ép áp lại password của `managed.roles` (CNPG chỉ áp ở lần reconcile kế tiếp):

```bash
kubectl rollout restart deployment cnpg-operator-cloudnative-pg -n cnpg-system
```

Thử dữ liệu bền qua restart:

```bash
kubectl delete pod postgres-1 -n infra
kubectl get pvc -n infra
```
