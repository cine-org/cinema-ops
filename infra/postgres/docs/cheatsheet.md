# Postgres cheatsheet

```bash
kubectl get cluster,pods -n infra -l cnpg.io/cluster=postgres
kubectl get cluster postgres -n infra -o jsonpath='{.status.managedRolesStatus}'; echo
kubectl exec -it -n infra postgres-1 -- psql -U postgres -d cinema
```

Ép áp lại password của `managed.roles` (CNPG chỉ áp ở lần reconcile kế tiếp):

```bash
kubectl rollout restart deployment cnpg-operator-cloudnative-pg -n cnpg-system
```
