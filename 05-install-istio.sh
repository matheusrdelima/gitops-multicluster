#!/usr/bin/env bash
# =============================================================================
# Script: 05-install-istio.sh
# Descrição: Instala Istio nos clusters shard-1 e shard-2
# Execução: bash scripts/05-install-istio.sh
# =============================================================================
set -euo pipefail

ISTIO_VERSION="1.21.2"
KUBECONFIG_MERGED="$HOME/.kube/multicluster/merged.yaml"

export KUBECONFIG="$KUBECONFIG_MERGED"

install_istio_on_cluster() {
  local context=$1
  local cluster_name=$2

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "=== Instalando Istio no cluster: $cluster_name ==="
  echo "════════════════════════════════════════════════════════════════"

  kubectl config use-context "$context"

  # Verifica e baixa istioctl se necessário
  if ! command -v istioctl &>/dev/null; then
    echo "  📥 Baixando istioctl v${ISTIO_VERSION}..."
    cd /tmp
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
    export PATH="$PWD/istio-${ISTIO_VERSION}/bin:$PATH"
    cd -
  fi

  echo "  ⚙️ Instalando perfil 'default'..."
  istioctl install \
    --context "$context" \
    --set profile=default \
    --set values.global.meshID=mesh1 \
    --set values.global.multiCluster.clusterName="$cluster_name" \
    --set values.global.network=network1 \
    -y

  echo ""
  echo "  📦 Criando namespace hello-app..."
  kubectl create namespace hello-app --dry-run=client -o yaml | \
    kubectl apply -f -

  echo "  🏷️ Habilitando injeção de Envoy sidecar..."
  kubectl label namespace hello-app istio-injection=enabled --overwrite

  echo "  ✅ Istio instalado no cluster: $cluster_name"
}

echo "=== Verificando istioctl ==="

if ! command -v istioctl &>/dev/null; then
  echo "  istioctl não encontrado — será baixado durante instalação"
else
  echo "  ✅ istioctl já instalado: $(istioctl version --short)"
fi

echo ""

# Instala nos dois shards
install_istio_on_cluster "cluster-shard-1" "shard-1"
install_istio_on_cluster "cluster-shard-2" "shard-2"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "=== ✅ Istio instalado em ambos os shards ==="
echo "════════════════════════════════════════════════════════════════"

# Verifica status
echo ""
echo "=== Status dos pods Istio ==="
for context in cluster-shard-1 cluster-shard-2; do
  echo ""
  echo "Cluster: $context"
  kubectl --context="$context" get pods -n istio-system
done
