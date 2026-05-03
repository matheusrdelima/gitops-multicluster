#!/usr/bin/env bash
# =============================================================================
# Script: 04-register-clusters.sh
# Descrição: Registra shard-1 e shard-2 no ArgoCD
# Execução: bash scripts/04-register-clusters.sh
# =============================================================================
set -euo pipefail

KUBECONFIG_MERGED="$HOME/.kube/multicluster/merged.yaml"
KUBECONFIG_ARGOCD="$HOME/.kube/multicluster/argocd-internal.yaml"
ARGOCD_NS="argocd"

export KUBECONFIG="$KUBECONFIG_MERGED"

wait_for_argocd() {
  local retries=12
  local wait=5

  echo "=== Verificando disponibilidade do ArgoCD via NodePort..."
  for i in $(seq 1 "$retries"); do
    if curl -k --silent --max-time 5 https://localhost:30088 >/dev/null 2>&1; then
      echo "  ✅ ArgoCD disponível em https://localhost:30088"
      return 0
    fi
    echo "  ⏳ Aguardando ArgoCD responder na porta 30088 ($i/$retries)..."
    sleep "$wait"
  done

  echo "❌ ArgoCD não respondeu em https://localhost:30088 após $((retries * wait))s"
  return 1
}

echo "=== Obtendo senha do ArgoCD ==="
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n "$ARGOCD_NS" \
  -o jsonpath="{.data.password}" | base64 -d)

echo "✅ Senha obtida"

echo ""
wait_for_argocd

echo "=== Fazendo login no ArgoCD ==="
login_ok=0
set +e
for i in $(seq 1 8); do
  if argocd login localhost:30088 \
    --username admin \
    --password "$ARGOCD_PASS" \
    --insecure \
    --grpc-web \
    --skip-test-tls \
    --http-retry-max 20 >/dev/null 2>&1; then
    login_ok=1
    echo "  ✅ Login realizado no ArgoCD"
    break
  fi
  echo "  ⏳ Tentativa $i de login falhou, aguardando..."
  sleep 5
done
set -e
if [ "$login_ok" -ne 1 ]; then
  echo "❌ Não foi possível efetuar login no ArgoCD após várias tentativas"
  exit 1
fi

echo ""
echo "=== Registrando cluster shard-1 ==="
echo "  Aguardando cluster shard-1 estabilizar..."
sleep 10
argocd cluster add cluster-shard-1 \
  --kubeconfig "$KUBECONFIG_ARGOCD" \
  --name shard-1 \
  --yes \
  --insecure

echo ""
echo "=== Registrando cluster shard-2 ==="
echo "  Aguardando cluster shard-2 estabilizar..."
sleep 5
argocd cluster add cluster-shard-2 \
  --kubeconfig "$KUBECONFIG_ARGOCD" \
  --name shard-2 \
  --yes \
  --insecure

echo ""
echo "=== Clusters registrados ==="
argocd cluster list

echo ""
echo "=== ✅ Registro concluído ==="
