════════════════════════════════════════════════════════════════════════
🎯 GUIA OPERACIONAL: ApplicationSet como Fonte Única de Verdade
════════════════════════════════════════════════════════════════════════

O ApplicationSet está em: argocd/applicationsets/hello-appset.yaml

Cada ELEMENTO no campo "elements:" representa:
  ├─ cluster:  qual cluster (shard-1, shard-2)
  ├─ image:    qual imagem Docker usar
  ├─ version:  identificador de versão (v1, v2)
  ├─ shadow:   "true" = tráfego espelhado | "false" = tráfego real
  └─ weight:   % de tráfego real (ignorado quando shadow=true)

────────────────────────────────────────────────────────────────────────
OPERAÇÕES BÁSICAS
────────────────────────────────────────────────────────────────────────

✅ VERIFICAR STATUS

  # Ver todas as Applications criadas pelo AppSet
  kubectl --context=cluster-master -n argocd get applications
  
  # Ver status de sincronização
  argocd app list
  
  # Detalhes de uma Application
  argocd app get hello-shard-1-v1
  argocd app get hello-shard-1-v2

✅ VERIFICAR PODS EM CADA SHARD

  # Verificar pods em shard-1
  kubectl --context=cluster-shard-1 -n hello-app get pods -l app=hello-service
  
  # Labels: traffic.role=real ou traffic.role=shadow
  kubectl --context=cluster-shard-1 -n hello-app get pods -L traffic.role,version

✅ VER LOGS DO SHADOW

  # Logs da versão v2 (shadow) — procure por "shadow" ou ROLE:shadow
  kubectl --context=cluster-shard-1 -n hello-app logs -l version=v2 -f

  # Logs da versão v1 (real) — procure por ROLE:real
  kubectl --context=cluster-shard-1 -n hello-app logs -l version=v1 -f

────────────────────────────────────────────────────────────────────────
CENÁRIO 1: DESATIVAR SHADOW (remover v2 do espelho)
────────────────────────────────────────────────────────────────────────

ANTES: Arquivo argocd/applicationsets/hello-appset.yaml
  elements:
    - cluster: shard-1, version: v1, shadow: false, weight: 100
    - cluster: shard-1, version: v2, shadow: true,  weight: 0  ← REMOVA ESTA LINHA

DEPOIS: Remova o elemento com version=v2 e shadow=true

  elementos:
    - cluster: shard-1, version: v1, shadow: false, weight: 100
    # Elemento v2 removido

RESULTADO:
  - ArgoCD deletará a Application hello-shard-1-v2
  - Deployment hello-v2 será destruído
  - Subset "shadow" fica vazio
  - Istio para de espelhar requests

COMANDO:
  git add argocd/applicationsets/hello-appset.yaml
  git commit -m "Disable shadow: remove v2 from shard-1"
  git push
  
  # ArgoCD detecta em ~3 minutos (ou trigger webhook)
  # Verifique:
  argocd app list | grep shard-1

────────────────────────────────────────────────────────────────────────
CENÁRIO 2: PROMOVER v2 PARA PRODUÇÃO
────────────────────────────────────────────────────────────────────────

SITUAÇÃO: v1 está em produção, v2 passou no shadow test

MUDANÇA: Inverta shadow e weights

ANTES:
  - cluster: shard-1, version: v1, shadow: false, weight: 100
  - cluster: shard-1, version: v2, shadow: true,  weight: 0

DEPOIS:
  - cluster: shard-1, version: v1, shadow: true,  weight: 0   ← inverted
  - cluster: shard-1, version: v2, shadow: false, weight: 100 ← inverted

RESULTADO:
  - VirtualService agora criado por v2 (shadow=false)
  - Route: 100% do tráfego para v2 (real)
  - Mirror: espelha tráfego para v1 (novo shadow — rollback fácil)
  - Usuários veem respostas de v2

ROLLBACK (volta para v1):
  Se v2 tiver problema, inverta novamente (2 min no máximo)

COMANDO:
  git add argocd/applicationsets/hello-appset.yaml
  git commit -m "Promote v2 to production in shard-1"
  git push

────────────────────────────────────────────────────────────────────────
CENÁRIO 3: CANARY 90/10 (SEM Argo Rollouts, apenas Istio)
────────────────────────────────────────────────────────────────────────

SITUAÇÃO: Quer enviar 10% do tráfego para v2 enquanto testa

MUDANÇA: Ambas com shadow=false, pesos divididos

ANTES:
  - cluster: shard-1, version: v1, shadow: false, weight: 100
  - cluster: shard-1, version: v2, shadow: true,  weight: 0

DEPOIS:
  - cluster: shard-1, version: v1, shadow: false, weight: 90   ← 90% real
  - cluster: shard-1, version: v2, shadow: false, weight: 10   ← 10% real

RESULTADO:
  - VirtualService renderizado (por v1, shadow=false)
  - Route: 90% v1 + 10% v2 (SEM mirror — ambos servem usuários)
  - Ambos recebem tráfego real
  - Métricas diferenciadas por label version

PRÓXIMOS PASSOS (gradual):
  Incremente v2: 90/10 → 80/20 → 70/30 → 60/40 → 50/50 → ... → 0/100

COMANDO:
  git add argocd/applicationsets/hello-appset.yaml
  git commit -m "Start canary: shard-1 v1=90% v2=10%"
  git push

  # Depois de 1 hora e análise:
  git commit -am "Increase canary: shard-1 v1=80% v2=20%"
  git push
  
  # ... repita até 100%

────────────────────────────────────────────────────────────────────────
CENÁRIO 4: DEPLOYAR v3 COMO NOVO SHADOW (2 shadows simultâneos)
────────────────────────────────────────────────────────────────────────

SITUAÇÃO: Quer testar v3 enquanto v2 continua sendo shadow de v1

MUDANÇA: Adicione novo elemento com version=v3

ANTES:
  - cluster: shard-1, version: v1, shadow: false, weight: 100
  - cluster: shard-1, version: v2, shadow: true,  weight: 0

DEPOIS:
  - cluster: shard-1, version: v1, shadow: false, weight: 100
  - cluster: shard-1, version: v2, shadow: true,  weight: 0
  - cluster: shard-1, version: v3, shadow: true,  weight: 0  ← NOVO!

RESULTADO:
  - Ambos v2 e v3 rodam no mesmo cluster
  - Ambos recebem tráfego espelhado (100% cada um, independentemente)
  - VirtualService: mirror duplo → v2 E v3
  - Usuário recebe resposta de v1
  - Logs: v1 [ROLE:real], v2 [ROLE:shadow], v3 [ROLE:shadow]

NOTA: Mirror duplo não é possível nativamente no Istio.
      Alternativa: use weight canary para um deles
      
      - cluster: shard-1, version: v1, shadow: false, weight: 95
      - cluster: shard-1, version: v2, shadow: true,  weight: 0   (mirror 100%)
      - cluster: shard-1, version: v3, shadow: false, weight: 5   (canary 5%)

════════════════════════════════════════════════════════════════════════
FLUXO PADRÃO DE DEPLOY (Production)
════════════════════════════════════════════════════════════════════════

1. Versão v1 roda em SHARD-1 e SHARD-2 (shadow=false, weight=100)

2. Nova versão v2 é testada:
   ├─ Add elemento: version=v2, shadow=true em ambos shards
   ├─ Istio espelha 100% do tráfego para v2
   ├─ Nenhum usuário afetado
   ├─ Logs monitorados por 24h
   └─ Se estável → próximo passo

3. Canary em SHARD-1:
   ├─ v1 weight=80, v2 weight=20 (ambas real)
   ├─ Monitor por 2h
   ├─ Se estável, aumente: v1=60, v2=40

4. Promove em SHARD-1 completamente:
   ├─ v1 shadow=true, v2 shadow=false (invert)
   ├─ v2 agora em produção

5. Canary em SHARD-2:
   ├─ Repita passos 3-4 para shard-2

6. Cleanup:
   ├─ Remova versão v1 após confirmação em ambos shards
   └─ v2 fica como "stable"

════════════════════════════════════════════════════════════════════════
VERIFICAÇÕES IMPORTANTES
════════════════════════════════════════════════════════════════════════

✅ Verificar status do ApplicationSet:
   kubectl --context=cluster-master -n argocd get applicationset hello-appset
   kubectl --context=cluster-master -n argocd describe applicationset hello-appset

✅ Verificar Applications geradas:
   kubectl --context=cluster-master -n argocd get applications -l app=hello-service

✅ Verificar sincronização:
   argocd app list | grep hello

✅ Ver labels dos pods (identifica shadow vs real):
   kubectl --context=cluster-shard-1 -n hello-app get pods \
     -o custom-columns=POD:.metadata.name,VERSION:.metadata.labels.version,ROLE:.metadata.labels.traffic.role

✅ Ver tráfego sendo espelhado:
   # Terminal 1: tail logs de v1 (real)
   kubectl --context=cluster-shard-1 -n hello-app logs -f -l version=v1 | grep hello
   
   # Terminal 2: tail logs de v2 (shadow)
   kubectl --context=cluster-shard-1 -n hello-app logs -f -l version=v2 | grep hello
   
   # Terminal 3: envie requisições
   while true; do
     curl http://localhost:8080/hello
     sleep 1
   done

════════════════════════════════════════════════════════════════════════
CHEAT SHEET
════════════════════════════════════════════════════════════════════════

# Editar ApplicationSet no cluster master
kubectl --context=cluster-master -n argocd edit applicationset hello-appset

# Forçar sincronização de uma Application
argocd app sync hello-shard-1-v1
argocd app sync hello-shard-1-v2

# Deletar uma Application (se removida do AppSet)
kubectl --context=cluster-master -n argocd delete application hello-shard-1-v2

# Ver definição completa de uma Application
kubectl --context=cluster-master -n argocd get application hello-shard-1-v1 -o yaml

# Port-forward para testar endpoint
kubectl --context=cluster-shard-1 -n hello-app port-forward svc/hello-svc 8080:80

# curl no endpoint
curl -X GET http://localhost:8080/hello -H "Content-Type: application/json" | jq .

# Escalar pods manualmente (não recomendado — deixe ArgoCD fazer)
kubectl --context=cluster-shard-1 -n hello-app scale deployment hello-v1 --replicas=3

════════════════════════════════════════════════════════════════════════
