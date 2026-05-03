#!/usr/bin/env bash
# =============================================================================
# Script: 01-create-clusters.sh
# Descrição: Cria os 3 clusters KIND (master, shard-1, shard-2)
# Execução: bash scripts/01-create-clusters.sh
# =============================================================================
set -euo pipefail

MASTER_NAME="master"
SHARD1_NAME="shard-1"
SHARD2_NAME="shard-2"

MASTER_POD_CIDR="10.10.0.0/16"
MASTER_SVC_CIDR="10.11.0.0/16"

SHARD1_POD_CIDR="10.20.0.0/16"
SHARD1_SVC_CIDR="10.21.0.0/16"

SHARD2_POD_CIDR="10.30.0.0/16"
SHARD2_SVC_CIDR="10.31.0.0/16"

# Portas para cada cluster (evitando conflitos)
MASTER_API_PORT=6443
MASTER_NODEPORT_30080=6543
MASTER_NODEPORT_30443=6544
MASTER_NODEPORT_30088=30088

SHARD1_API_PORT=6444
SHARD1_NODEPORT_30080=6643
SHARD1_NODEPORT_30443=6644

SHARD2_API_PORT=6445
SHARD2_NODEPORT_30080=6743
SHARD2_NODEPORT_30443=6744

check_ports() {
  local ports=($MASTER_API_PORT $MASTER_NODEPORT_30080 $MASTER_NODEPORT_30443 $MASTER_NODEPORT_30088 $SHARD1_API_PORT $SHARD1_NODEPORT_30080 $SHARD1_NODEPORT_30443 $SHARD2_API_PORT $SHARD2_NODEPORT_30080 $SHARD2_NODEPORT_30443)
  local occupied_ports=()

  echo "=== Verificando disponibilidade das portas ==="
  for port in "${ports[@]}"; do
    if lsof -i :$port >/dev/null 2>&1; then
      occupied_ports+=($port)
      echo "  ❌ Porta $port: OCUPADA"
    else
      echo "  ✅ Porta $port: LIVRE"
    fi
  done

  if [ ${#occupied_ports[@]} -gt 0 ]; then
    echo ""
    echo "❌ ERRO: As seguintes portas estão ocupadas: ${occupied_ports[*]}"
    echo "   Execute o script de limpeza primeiro:"
    echo "   bash cleanup.sh"
    exit 1
  fi
  echo ""
}

create_cluster() {
  local name=$1
  local pod_cidr=$2
  local svc_cidr=$3
  local api_port=$4
  local nodeport_30080=$5
  local nodeport_30443=$6
  local nodeport_30088=${7:-}  # Opcional, apenas para master

  echo ">>> Criando cluster: $name"

  cat <<EOF | kind create cluster --name "$name" --config=-
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster

networking:
  podSubnet:     "$pod_cidr"
  serviceSubnet: "$svc_cidr"
  disableDefaultCNI: false

nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 6443
        hostPort: $api_port
        protocol: TCP
      - containerPort: 30080
        hostPort: $nodeport_30080
        protocol: TCP
      - containerPort: 30443
        hostPort: $nodeport_30443
        protocol: TCP
$(if [ -n "$nodeport_30088" ]; then
  echo "      - containerPort: 30088
        hostPort: $nodeport_30088
        protocol: TCP"
fi)

  - role: worker
    labels:
      topology.kubernetes.io/zone: zone-a

  - role: worker
    labels:
      topology.kubernetes.io/zone: zone-b
EOF

  echo "✅ Cluster '$name' criado com sucesso."
}

echo "=== Verificando pré-requisitos ==="
command -v kind    >/dev/null || { echo "❌ 'kind' não encontrado."; exit 1; }
command -v kubectl >/dev/null || { echo "❌ 'kubectl' não encontrado."; exit 1; }
command -v docker  >/dev/null || { echo "❌ 'docker' não encontrado."; exit 1; }

docker info >/dev/null 2>&1 || { echo "❌ Docker não está rodando."; exit 1; }

echo ""
echo "=== Removendo clusters existentes (se houver) ==="
for cluster in $MASTER_NAME $SHARD1_NAME $SHARD2_NAME; do
  if kind get clusters 2>/dev/null | grep -q "^${cluster}$"; then
    echo "  Deletando cluster: $cluster"
    kind delete cluster --name "$cluster"
  fi
done

# Aguardar limpeza dos containers Docker
echo "  Aguardando limpeza dos containers Docker..."
sleep 5

# Forçar remoção de containers KIND que podem ter ficado
echo "  Removendo containers KIND remanescentes..."
docker ps -a --filter "label=io.x-k8s.kind.cluster" -q 2>/dev/null | xargs docker rm -f 2>/dev/null || true

# Aguardar liberação das portas
echo "  Aguardando liberação das portas..."
sleep 3

echo ""
echo "=== Criando clusters KIND ==="

check_ports

create_cluster "$MASTER_NAME" "$MASTER_POD_CIDR" "$MASTER_SVC_CIDR" "$MASTER_API_PORT" "$MASTER_NODEPORT_30080" "$MASTER_NODEPORT_30443" "$MASTER_NODEPORT_30088"
create_cluster "$SHARD1_NAME" "$SHARD1_POD_CIDR" "$SHARD1_SVC_CIDR" "$SHARD1_API_PORT" "$SHARD1_NODEPORT_30080" "$SHARD1_NODEPORT_30443"
create_cluster "$SHARD2_NAME" "$SHARD2_POD_CIDR" "$SHARD2_SVC_CIDR" "$SHARD2_API_PORT" "$SHARD2_NODEPORT_30080" "$SHARD2_NODEPORT_30443"

echo ""
echo "=== ✅ Todos os clusters criados! ==="
kind get clusters
