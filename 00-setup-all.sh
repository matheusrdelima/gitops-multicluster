#!/usr/bin/env bash
# =============================================================================
# Script: 00-setup-all.sh
# Descrição: Orquestra toda a setup (executar na sua máquina local)
# =============================================================================
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                  SETUP MULTICLUSTER GITOPS                         ║"
echo "║          ApplicationSet + Istio + Helm Shadow Testing             ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"
KUBECONFIG_MERGED="$HOME/.kube/multicluster/merged.yaml"

# ─── Etapa 1: Criar clusters KIND ──────────────────────────────────────────
echo ""
echo "📋 ETAPA 1: Criar clusters KIND (master, shard-1, shard-2)"
echo "════════════════════════════════════════════════════════════════════"
if [ -f "$SCRIPT_DIR/01-create-clusters.sh" ]; then
  bash "$SCRIPT_DIR/01-create-clusters.sh"
else
  echo "❌ Script 01-create-clusters.sh não encontrado em $SCRIPT_DIR"
  exit 1
fi

# ─── Etapa 2: Setup kubeconfig ────────────────────────────────────────────
echo ""
echo "📋 ETAPA 2: Configurar kubeconfig"
echo "════════════════════════════════════════════════════════════════════"
bash "$SCRIPT_DIR/02-setup-kubeconfig.sh"

# ─── Etapa 3: Instalar ArgoCD no master ───────────────────────────────────
echo ""
echo "📋 ETAPA 3: Instalar ArgoCD no cluster master"
echo "════════════════════════════════════════════════════════════════════"
export KUBECONFIG="$KUBECONFIG_MERGED"
bash "$SCRIPT_DIR/03-install-argocd.sh"

# ─── Etapa 4: Registrar clusters no ArgoCD ────────────────────────────────
echo ""
echo "📋 ETAPA 4: Registrar clusters shard-1 e shard-2 no ArgoCD"
echo "════════════════════════════════════════════════════════════════════"
bash "$SCRIPT_DIR/04-register-clusters.sh"

# ─── Etapa 5: Instalar Istio nos shards ───────────────────────────────────
echo ""
echo "📋 ETAPA 5: Instalar Istio nos clusters shard-1 e shard-2"
echo "════════════════════════════════════════════════════════════════════"
bash "$SCRIPT_DIR/05-install-istio.sh"

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                     ✅ SETUP CONCLUÍDO!                            ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Próximos passos:"
echo ""
echo "1️⃣  Compile e carregue as imagens Docker:"
echo "   cd apps/hello-service"
echo "   docker build -t hello-service:v1.0.0 ."
echo "   docker build -t hello-service:v2.0.0 ."
echo "   kind load docker-image hello-service:v1.0.0 --name shard-1"
echo "   kind load docker-image hello-service:v1.0.0 --name shard-2"
echo "   kind load docker-image hello-service:v2.0.0 --name shard-1"
echo "   kind load docker-image hello-service:v2.0.0 --name shard-2"
echo ""
echo "2️⃣  Configure Git e push do repositório:"
echo "   git init ."
echo "   git add ."
echo "   git commit -m 'Initial commit: ApplicationSet + Helm chart'"
echo "   git remote add origin <seu-repo>"
echo "   git push -u origin main"
echo ""
echo "3️⃣  Aplique o ApplicationSet:"
echo "   kubectl --kubeconfig=$KUBECONFIG_MERGED config use-context cluster-master"
echo "   kubectl apply -f argocd/applicationsets/hello-appset.yaml"
echo ""
echo "4️⃣  Acompanhe o deploy no ArgoCD:"
echo "   https://localhost:30088"
echo "   (User: admin, Senha: <gerada acima>)"
echo ""
echo "5️⃣  Teste o endpoint:"
echo "   kubectl --context=cluster-shard-1 -n hello-app port-forward svc/hello-svc 8080:80 &"
echo "   curl http://localhost:8080/hello"
echo ""
