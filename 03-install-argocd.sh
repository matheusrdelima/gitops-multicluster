#!/usr/bin/env bash
# =============================================================================
# Script: 03-install-argocd.sh
# Descrição: Instala ArgoCD no cluster MASTER
# Execução: bash scripts/03-install-argocd.sh
# =============================================================================
set -euo pipefail

ARGOCD_VERSION="v2.11.0"
ARGOCD_NS="argocd"
KUBECONFIG_MERGED="$HOME/.kube/multicluster/merged.yaml"

export KUBECONFIG="$KUBECONFIG_MERGED"

echo "=== Instalando ArgoCD no cluster MASTER ==="
echo "  Versão: $ARGOCD_VERSION"

kubectl config use-context cluster-master

kubectl create namespace "$ARGOCD_NS" --dry-run=client -o yaml | \
  kubectl apply -f -

echo "  Aplicando manifesto oficial do ArgoCD..."
kubectl apply -n "$ARGOCD_NS" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "  Aguardando ArgoCD ficar pronto (pode demorar ~2 min)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n "$ARGOCD_NS" \
  --timeout=300s

echo ""
echo "  Expondo ArgoCD via NodePort na porta 30088..."
kubectl patch svc argocd-server \
  -n "$ARGOCD_NS" \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8080,"nodePort":30088}]}}'

echo ""
echo "  Aguardando service estar pronto..."
for i in {1..12}; do
  if curl -k --silent --max-time 5 https://localhost:30088 >/dev/null 2>&1; then
    echo "  ✅ ArgoCD disponível em https://localhost:30088"
    break
  fi
  echo "  ⏳ Aguardando ArgoCD responder na porta 30088 ($i/12)..."
  sleep 5
done

echo ""
echo "=== 🔑 Credenciais do ArgoCD ==="

ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret \
  -n "$ARGOCD_NS" \
  -o jsonpath="{.data.password}" | base64 -d)

echo "  URL:  https://localhost:30088"
echo "  User: admin"
echo "  Pass: $ARGOCD_PASS"
echo ""
echo "  ⚠️ Aceite o certificado autoassinado no navegador"
echo ""
echo "=== ✅ ArgoCD instalado ==="
