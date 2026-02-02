#!/bin/bash

# Deploy Simples BIA - Versionamento por Commit Hash
set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

# Obter commit hash
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "🚀 Deploy BIA - Versão: $COMMIT_HASH"

# Login ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URI

# Build e Push
docker build -t $ECR_URI:$COMMIT_HASH -t $ECR_URI:latest .
docker push $ECR_URI:$COMMIT_HASH
docker push $ECR_URI:latest

# Obter task definition atual
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition')

# Criar nova task definition
NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg image "$ECR_URI:$COMMIT_HASH" '
    .containerDefinitions[0].image = $image |
    del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
')

# Registrar nova task definition
echo "$NEW_TASK_DEF" > /tmp/task-def.json
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file:///tmp/task-def.json --query 'taskDefinition.revision' --output text)
rm /tmp/task-def.json

# Atualizar serviço
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION

echo "✅ Deploy concluído - Versão: $COMMIT_HASH (Revision: $NEW_REVISION)"
