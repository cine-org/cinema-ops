# Redis cheatsheet

```bash
PW=$(kubectl get secret infra-redis -n infra -o jsonpath='{.data.password}' | base64 -d)
R="kubectl exec -n infra redis-0 -- env REDISCLI_AUTH=$PW redis-cli"
$R info replication
$R config get maxmemory-policy
$R dbsize
```

`REDISCLI_AUTH` thay `-a` để password không lộ trong danh sách tiến trình.

```bash
kubectl get pods -n infra -L redis-role
kubectl get endpointslice -n infra -l kubernetes.io/service-name=redis-master
```
