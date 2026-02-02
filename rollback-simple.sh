#!/bin/bash

# Rollback Simples BIA
set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

# Verificar parâmetro
if [ -z "$1" ]; then
    echo "❌ Uso: ./rollback-simple.sh <commit-hash>"
    echo "📋 Versões disponíveis:"
    aws ecr describe-images --repository-name $ECR_REPO --region $REGION --query 'imageDetails[*].imageTags[0]' --output table
    exit 1
fi

TARGET_TAG=$1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

echo "🔄 Rollback BIA - Versão: $TARGET_TAG"

# Verificar se imagem existe
aws ecr describe-images --repository-name $ECR_REPO --region $REGION --image-ids imageTag=$TARGET_TAG > /dev/null

# Obter task definition atual
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition')

# Criar nova task definition com imagem de rollback
NEW_TASK_DEF=$(echo $TASK_DEF | jq --arg image "$ECR_URI:$TARGET_TAG" '
    .containerDefinitions[0].image = $image |
    del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
')

# Registrar nova task definition
echo "$NEW_TASK_DEF" > /tmp/task-def.json
NEW_REVISION=$(aws ecs register-task-definition --region $REGION --cli-input-json file:///tmp/task-def.json --query 'taskDefinition.revision' --output text)
rm /tmp/task-def.json

# Atualizar serviço
aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$NEW_REVISION

echo "✅ Rollback concluído - Versão: $TARGET_TAG (Revision: $NEW_REVISION)"
