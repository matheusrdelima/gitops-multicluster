# 🚀 Multi-Cluster GitOps com ApplicationSet + Istio Shadow Testing

Ambiente local completo com **3 clusters KIND**, **ArgoCD**, **Istio**, e **Helm chart parametrizável**.

---

## 📋 Pré-requisitos

Instale na sua máquina:
- **Docker** (v20.10+) — https://docs.docker.com/get-docker/
- **kind** — `curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/`
- **kubectl** — https://kubernetes.io/docs/tasks/tools/
- **helm** — `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`
- **argocd CLI** — `curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v2.11.0/argocd-linux-amd64 && chmod +x argocd-linux-amd64 && sudo mv argocd-linux-amd64 /usr/local/bin/argocd`

---

## 📁 Estrutura do Projeto

```
gitops-multicluster/
│
├── apps/
│   └── hello-service/              # Código Java + Dockerfile
│       ├── src/main/java/com/example/hello/
│       │   ├── HelloApplication.java
│       │   └── HelloController.java
│       ├── src/main/resources/
│       │   └── application.yml
│       ├── pom.xml
│       └── Dockerfile
│
├── charts/
│   └── hello-service/              # Helm chart (renderização condicional)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── namespace.yaml
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── destinationrule.yaml
│           ├── virtualservice.yaml
│           └── gateway.yaml
│
├── argocd/
│   └── applicationsets/
│       └── hello-appset.yaml      # 🎯 ÚNICA FONTE DE VERDADE
│
├── scripts/
│   ├── 00-setup-all.sh           # Orquestra tudo
│   ├── 01-create-clusters.sh     # Cria 3 clusters KIND
│   ├── 02-setup-kubeconfig.sh    # Configura contextos
│   ├── 03-install-argocd.sh      # Instala ArgoCD
│   ├── 04-register-clusters.sh   # Registra clusters no ArgoCD
│   └── 05-install-istio.sh       # Instala Istio
│
└── README.md (este arquivo)
```

---

## 🚀 Execução Rápida

### 1. Clone ou crie o repositório

```bash
# Crie localmente:
mkdir gitops-multicluster
cd gitops-multicluster

# Copie os arquivos da estrutura acima
```

### 2. Compile as imagens Docker

```bash
cd apps/hello-service

# Versão v1.0.0
docker build -t hello-service:v1.0.0 .

# Versão v2.0.0 (reutiliza layers do v1)
docker build -t hello-service:v2.0.0 .
```

### 3. Crie os clusters KIND

```bash
bash scripts/01-create-clusters.sh
```

**Tempo esperado:** ~3-5 minutos

Você terá:
- `master` (API: localhost:6443)
- `shard-1` (API: localhost:6444)
- `shard-2` (API: localhost:6445)

### 4. Configure kubeconfig

```bash
bash scripts/02-setup-kubeconfig.sh

# Configure seu shell (escolha um):
# Bash:
echo 'export KUBECONFIG="$HOME/.kube/multicluster/merged.yaml"' >> ~/.bashrc
source ~/.bashrc

# Zsh:
echo 'export KUBECONFIG="$HOME/.kube/multicluster/merged.yaml"' >> ~/.zshrc
source ~/.zshrc
```

Verifique:
```bash
kubectl config get-contexts
# Deve mostrar: cluster-master, cluster-shard-1, cluster-shard-2
```

### 5. Instale ArgoCD

```bash
bash scripts/03-install-argocd.sh
```

**Tempo esperado:** ~2 minutos

Credenciais geradas — salve a senha!

Acesse: https://localhost:30088

### 6. Registre clusters no ArgoCD

```bash
bash scripts/04-register-clusters.sh
```

Verifique:
```bash
argocd cluster list
# Deve mostrar: shard-1 e shard-2 registrados
```

### 7. Instale Istio

```bash
bash scripts/05-install-istio.sh
```

**Tempo esperado:** ~3-4 minutos por cluster

Verifique:
```bash
kubectl --context=cluster-shard-1 -n istio-system get pods
```

### 8. Carregue as imagens Docker nos clusters

```bash
kind load docker-image hello-service:v1.0.0 --name shard-1
kind load docker-image hello-service:v1.0.0 --name shard-2
kind load docker-image hello-service:v2.0.0 --name shard-1
kind load docker-image hello-service:v2.0.0 --name shard-2
```

Verifique:
```bash
docker exec shard-1-control-plane crictl images | grep hello-service
```

### 9. Push do repositório Git

```bash
# Inicialize Git
git init .
git add .
git commit -m "Initial commit: ApplicationSet + Helm chart"

# Configure seu repositório remoto
git remote add origin https://github.com/seu-usuario/gitops-multicluster.git
git branch -M main
git push -u origin main
```

### 10. Aplique o ApplicationSet

```bash
kubectl config use-context cluster-master

# IMPORTANTE: Atualize a URL do repositório no ApplicationSet antes!
# Abra: argocd/applicationsets/hello-appset.yaml
# Mude: repoURL: https://github.com/seu-usuario/gitops-multicluster.git

kubectl apply -f argocd/applicationsets/hello-appset.yaml

# Verifique:
kubectl -n argocd get applicationset hello-appset
argocd app list
```

---

## 🧪 Testando o Deploy

### Ver Applications criadas

```bash
kubectl --context=cluster-master -n argocd get applications
# Deve mostrar 4 Applications:
# - hello-shard-1-v1
# - hello-shard-1-v2
# - hello-shard-2-v1
# - hello-shard-2-v2
```

### Verificar pods

```bash
kubectl --context=cluster-shard-1 -n hello-app get pods
# Deve mostrar:
# hello-v1-xxxxx (2 replicas) - traffic.role=real
# hello-v2-xxxxx (2 replicas) - traffic.role=shadow
```

### Testar endpoint

```bash
# Port-forward
kubectl --context=cluster-shard-1 -n hello-app port-forward svc/hello-svc 8080:80 &

# Fazer requisição
curl http://localhost:8080/hello | jq .

# Resposta esperada:
# {
#   "message": "Hello from v1!",
#   "version": "v1",
#   "trafficRole": "real",
#   "isShadow": false,
#   ...
# }
```

### Ver logs do shadow

```bash
# Terminal 1: v1 (recebendo tráfego real)
kubectl --context=cluster-shard-1 -n hello-app logs -f -l version=v1 | grep hello

# Terminal 2: v2 (recebendo tráfego espelhado)
kubectl --context=cluster-shard-1 -n hello-app logs -f -l version=v2 | grep shadow

# Terminal 3: envie requisições
while true; do
  curl http://localhost:8080/hello
  sleep 2
done
```

Você verá:
- **v1 logs**: `[ROLE:real]` — tráfego real dos usuários
- **v2 logs**: `[ROLE:shadow]` — tráfego espelhado pelo Istio

---

## 🎛️ Operações com ApplicationSet

O ApplicationSet está em `argocd/applicationsets/hello-appset.yaml`.

Cada **elemento** controla um deploy:
```yaml
- cluster:  shard-1
  version:  v1
  shadow:   "false"  # tráfego real
  weight:   "100"    # 100% do tráfego
```

### Desativar Shadow

Remova a linha com `version: v2, shadow: true`:

```bash
# Edit
kubectl --context=cluster-master -n argocd edit applicationset hello-appset

# Ou via Git
git commit -am "Disable shadow v2 in shard-1"
git push
# ArgoCD detecta em ~3 minutos
```

### Promover v2 para Produção

Inverta shadow e weights:

```yaml
# Antes
- cluster: shard-1, version: v1, shadow: false, weight: 100
- cluster: shard-1, version: v2, shadow: true,  weight: 0

# Depois (invert)
- cluster: shard-1, version: v1, shadow: true,  weight: 0
- cluster: shard-1, version: v2, shadow: false, weight: 100
```

### Canary 90/10

Ambas como `shadow: false` com pesos:

```yaml
- cluster: shard-1, version: v1, shadow: false, weight: 90
- cluster: shard-1, version: v2, shadow: false, weight: 10
```

---

## 📊 Arquitetura

```
┌─────────────────────────────────────────┐
│       CLUSTER MASTER                    │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  ArgoCD (https://localhost:30088)   │
│  │  ApplicationSet Controller      │   │
│  └─────────────────────────────────┘   │
│         │                               │
│         │ gerencia                      │
└─────────┼───────────────────────────────┘
          │
    ┌─────┴──────┐
    ▼            ▼
┌────────┐  ┌────────┐
│SHARD-1 │  │SHARD-2 │
│        │  │        │
│ Istio  │  │ Istio  │
│ ┌────┐ │  │ ┌────┐ │
│ │v1  │ │  │ │v1  │ │ ← tráfego real (shadow=false)
│ │v2  │ │  │ │v2  │ │ ← tráfego espelhado (shadow=true)
│ └────┘ │  │ └────┘ │
│ VirtualService   │  │ VirtualService   │
│ DestinationRule  │  │ DestinationRule  │
│ Service          │  │ Service          │
└────────┘  └────────┘
```

---

## 🔍 Troubleshooting

### ArgoCD não conecta aos clusters

```bash
# Verifique registro
argocd cluster list

# Se vazio, registre novamente:
argocd cluster add cluster-shard-1 --name shard-1 --yes
argocd cluster add cluster-shard-2 --name shard-2 --yes
```

### ApplicationSet não gera Applications

```bash
# Verifique ApplicationSet
kubectl --context=cluster-master -n argocd describe applicationset hello-appset

# Verifique logs do controller
kubectl --context=cluster-master -n argocd logs -f deployment/argocd-applicationset-controller
```

### Pods não ficam prontos (ImagePullBackOff)

```bash
# Verifique se as imagens foram carregadas nos clusters
docker exec shard-1-control-plane crictl images | grep hello-service

# Se não existem, carregue:
kind load docker-image hello-service:v1.0.0 --name shard-1
```

### Istio não injeta sidecar

```bash
# Verifique label do namespace
kubectl --context=cluster-shard-1 get namespace hello-app -o yaml | grep istio

# Se não tiver, adicione:
kubectl --context=cluster-shard-1 label namespace hello-app istio-injection=enabled --overwrite
```

---

## 📚 Referências

- **ApplicationSet Docs**: https://argocd-applicationset.readthedocs.io/
- **Istio Mirror**: https://istio.io/latest/docs/tasks/traffic-management/mirroring/
- **KIND**: https://kind.sigs.k8s.io/
- **Helm**: https://helm.sh/

---

## 📝 Licença

MIT

---

**Última atualização**: 2024-2025
**Versão**: 1.0.0
