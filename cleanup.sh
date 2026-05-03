#!/usr/bin/env bash
# =============================================================================
# Script: cleanup.sh
# Descrição: Limpa completamente o ambiente KIND e Docker
# Execução: bash cleanup.sh
# =============================================================================
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                   🧹 LIMPEZA COMPLETA                             ║"
echo "║              KIND Clusters + Docker Containers                    ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# ─── Passo 1: Deletar clusters KIND ────────────────────────────────────
echo "1️⃣  Deletando clusters KIND..."
if command -v kind >/dev/null 2>&1; then
  clusters=$(kind get clusters 2>/dev/null || true)
  if [ -n "$clusters" ]; then
    echo "$clusters" | while read cluster; do
      echo "   ✓ Deletando: $cluster"
      kind delete cluster --name "$cluster" 2>/dev/null || true
    done
  else
    echo "   ℹ️  Nenhum cluster KIND encontrado"
  fi
else
  echo "   ⚠️  kind não está instalado, pulando..."
fi

echo ""

# ─── Passo 2: Parar containers Docker ──────────────────────────────────
echo "2️⃣  Parando containers Docker..."
running=$(docker ps -q 2>/dev/null || true)
if [ -n "$running" ]; then
  echo "   Parando containers em execução..."
  docker stop $running 2>/dev/null || true
else
  echo "   ℹ️  Nenhum container em execução"
fi

echo ""

# ─── Passo 3: Remover containers KIND ──────────────────────────────────
echo "3️⃣  Removendo containers KIND..."
kind_containers=$(docker ps -a --filter "label=io.x-k8s.kind.cluster" -q 2>/dev/null || true)
if [ -n "$kind_containers" ]; then
  echo "   Removendo $( echo "$kind_containers" | wc -l) containers KIND..."
  echo "$kind_containers" | xargs docker rm -f 2>/dev/null || true
else
  echo "   ℹ️  Nenhum container KIND encontrado"
fi

echo ""

# ─── Passo 4: Remover redes Docker KIND ────────────────────────────────
echo "4️⃣  Removendo redes Docker KIND..."
networks=$(docker network ls --filter "name=kind" -q 2>/dev/null || true)
if [ -n "$networks" ]; then
  echo "   Removendo redes..."
  echo "$networks" | xargs docker network rm 2>/dev/null || true
else
  echo "   ℹ️  Nenhuma rede KIND encontrada"
fi

echo ""

# ─── Passo 5: Limpar kubeconfig ────────────────────────────────────────
echo "5️⃣  Limpando kubeconfig..."
KUBECONFIG_DIR="$HOME/.kube/multicluster"
if [ -d "$KUBECONFIG_DIR" ]; then
  echo "   Removendo diretório: $KUBECONFIG_DIR"
  rm -rf "$KUBECONFIG_DIR"
  echo "   ✓ Diretório removido"
else
  echo "   ℹ️  Diretório kubeconfig não existe"
fi

echo ""

# ─── Passo 6: Verificar portas ────────────────────────────────────────
echo "6️⃣  Verificando portas ocupadas..."
echo ""

ports_occupied=0
for port in 6443 6444 6445 6544 6545 6644 6645 6744 6745 30088 30080 30443; do
  if command -v lsof >/dev/null 2>&1; then
    if lsof -i :$port >/dev/null 2>&1; then
      echo "   ❌ Porta $port AINDA OCUPADA"
      echo "      Processos:"
      lsof -i :$port | tail -n +2 | awk '{print "        PID: " $2 ", Comando: " $1}'
      ports_occupied=$((ports_occupied + 1))
    else
      echo "   ✅ Porta $port: LIVRE"
    fi
  else
    echo "   ⚠️  'lsof' não instalado, não é possível verificar porta $port"
  fi
done

echo ""

if [ $ports_occupied -gt 0 ]; then
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║ ⚠️  AVISO: Ainda há portas ocupadas                                ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Para liberar uma porta manualmente:"
  echo ""
  echo "  # Linux/Mac"
  echo "  sudo lsof -i :PORTA"
  echo "  sudo kill -9 PID"
  echo ""
  echo "  # Ou use docker se for um container"
  echo "  docker ps -a | grep <nome>"
  echo "  docker rm -f <container-id>"
  echo ""
else
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║ ✅ LIMPEZA CONCLUÍDA COM SUCESSO!                                 ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
fi

echo ""
echo "Agora você pode executar:"
echo "  bash scripts/01-create-clusters.sh"
echo ""
