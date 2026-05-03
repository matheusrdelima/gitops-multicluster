#!/usr/bin/env bash
# =============================================================================
# Script: 02-setup-kubeconfig.sh
# Descrição: Configura contextos kubeconfig para alternar entre clusters
# Execução: bash scripts/02-setup-kubeconfig.sh
# =============================================================================
set -euo pipefail

KUBECONFIG_DIR="$HOME/.kube/multicluster"
mkdir -p "$KUBECONFIG_DIR"

# Detecta o IP local do host para que ArgoCD possa acessar os clusters via portas mapeadas.
# Em Docker Desktop, pods conseguem alcançar o host usando o IP da interface de rede.
detect_host_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip route get 1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'
  elif command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || ipconfig getifaddr en2 2>/dev/null
  else
    echo ""
  fi
}

HOST_IP="$(detect_host_ip)"
if [ -z "$HOST_IP" ]; then
  echo "❌ Não foi possível detectar o IP do host para o kubeconfig interno do ArgoCD."
  echo "   Defina a variável HOST_IP manualmente no script ou execute em um ambiente com ip/ipconfig disponíveis."
  exit 1
fi

echo "=== Exportando kubeconfigs individuais por cluster ==="

for cluster in master shard-1 shard-2; do
  echo "  Exportando: $cluster"

  kind export kubeconfig \
    --name "$cluster" \
    --kubeconfig "$KUBECONFIG_DIR/${cluster}.yaml" \
    --internal=false

  # Corrigir endereço do servidor de 0.0.0.0 para 127.0.0.1
  sed -i.bak 's/0\.0\.0\.0:6443/127.0.0.1:6443/g; s/0\.0\.0\.0:6444/127.0.0.1:6444/g; s/0\.0\.0\.0:6445/127.0.0.1:6445/g' "$KUBECONFIG_DIR/${cluster}.yaml"

  echo "  ✅ Salvo em: $KUBECONFIG_DIR/${cluster}.yaml"
done

echo ""
echo "=== Fazendo merge dos kubeconfigs ==="

echo ""
export KUBECONFIG="$KUBECONFIG_DIR/master.yaml:$KUBECONFIG_DIR/shard-1.yaml:$KUBECONFIG_DIR/shard-2.yaml"

MERGED_FILE="$KUBECONFIG_DIR/merged.yaml"

kubectl config view --flatten > "$MERGED_FILE"

echo "  ✅ Kubeconfig merged em: $MERGED_FILE"

echo ""
echo "=== Renomeando contextos ==="

echo ""

kubectl --kubeconfig "$MERGED_FILE" \
  config rename-context "kind-master"  "cluster-master" 2>/dev/null || true

kubectl --kubeconfig "$MERGED_FILE" \
  config rename-context "kind-shard-1" "cluster-shard-1" 2>/dev/null || true

kubectl --kubeconfig "$MERGED_FILE" \
  config rename-context "kind-shard-2" "cluster-shard-2" 2>/dev/null || true

echo "=== Criando kubeconfig específico para ArgoCD (acesso a partir do cluster) ==="

echo ""
# ArgoCD precisa de um kubeconfig que seja acessível a partir do pod/cluster.
# Usamos o IP do host, que é roteável tanto pelo host quanto pelos pods.
cp "$MERGED_FILE" "$KUBECONFIG_DIR/argocd-internal.yaml"

sed -i.bak -E \
  "s#https://127\\.0\\.0\\.1:6443#https://$HOST_IP:6443#g; s#https://127\\.0\\.0\\.1:6444#https://$HOST_IP:6444#g; s#https://127\\.0\\.0\\.1:6445#https://$HOST_IP:6445#g" \
  "$KUBECONFIG_DIR/argocd-internal.yaml"

sed -i.bak -E \
  's#^([[:space:]]*)certificate-authority(-data)?:.*#\1insecure-skip-tls-verify: true#g' \
  "$KUBECONFIG_DIR/argocd-internal.yaml"

echo "  ✅ Kubeconfig interno para ArgoCD criado em: $KUBECONFIG_DIR/argocd-internal.yaml"

rm -f "$KUBECONFIG_DIR"/*.bak

echo "  Contextos disponíveis:"
kubectl --kubeconfig "$MERGED_FILE" config get-contexts

echo ""
echo "=== 📋 Como usar ==="
echo ""
echo "  Adicione ao seu shell (~/.bashrc ou ~/.zshrc):"
echo "  export KUBECONFIG=\"$MERGED_FILE\""
echo ""
echo "  Depois execute: source ~/.bashrc"
echo ""
echo "  Comandos para alternar contextos:"
echo "  kubectl config use-context cluster-master"
echo "  kubectl config use-context cluster-shard-1"
echo "  kubectl config use-context cluster-shard-2"
