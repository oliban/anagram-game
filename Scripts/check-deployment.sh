#!/bin/bash

# Deployment Status Check Script
# Checks the health and status of all deployed services

set -e

ENVIRONMENT=${1:-staging}
REGION=${2:-eu-west-1}

echo "🔍 Checking deployment status for $ENVIRONMENT environment"
echo "=========================================================="
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
if ! command_exists aws; then
    echo "❌ AWS CLI not found. Please install it first."
    exit 1
fi

if ! command_exists curl; then
    echo "❌ curl not found. Please install it first."
    exit 1
fi

echo "📊 ECS Cluster Status"
echo "--------------------"

# Check if cluster exists
CLUSTER_NAME="anagram-$ENVIRONMENT"
if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "✅ Cluster $CLUSTER_NAME is active"
else
    echo "❌ Cluster $CLUSTER_NAME not found or not active"
    exit 1
fi

echo ""
echo "🚀 Service Status"
echo "----------------"

# Check each service
SERVICES=("game-server" "web-dashboard" "link-generator")

for service in "${SERVICES[@]}"; do
    SERVICE_NAME="anagram-$ENVIRONMENT-$service"
    
    # Get service status
    SERVICE_INFO=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$REGION" \
        --query 'services[0].{running:runningCount,desired:desiredCount,status:status,taskDefinition:taskDefinition}' \
        --output json 2>/dev/null)
    
    if [[ "$SERVICE_INFO" == "null" ]]; then
        echo "❌ Service $service: Not found"
        continue
    fi
    
    RUNNING=$(echo "$SERVICE_INFO" | jq -r '.running')
    DESIRED=$(echo "$SERVICE_INFO" | jq -r '.desired')
    STATUS=$(echo "$SERVICE_INFO" | jq -r '.status')
    TASK_DEF=$(echo "$SERVICE_INFO" | jq -r '.taskDefinition' | cut -d':' -f6)
    
    if [[ "$RUNNING" == "$DESIRED" && "$STATUS" == "ACTIVE" ]]; then
        echo "✅ Service $service: $RUNNING/$DESIRED running (revision $TASK_DEF)"
    else
        echo "⚠️  Service $service: $RUNNING/$DESIRED running, status: $STATUS"
    fi
done

echo ""
echo "🌐 Load Balancer Status"
echo "----------------------"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, 'anagram-$ENVIRONMENT')].DNSName" \
    --output text 2>/dev/null)

if [[ -n "$ALB_DNS" ]]; then
    echo "✅ Load Balancer: $ALB_DNS"
    
    echo ""
    echo "🏥 Health Checks"
    echo "---------------"
    
    # Test game server health
    echo -n "Game Server (/api/status): "
    if curl -sf --max-time 10 "http://$ALB_DNS/api/status" >/dev/null; then
        echo "✅ Healthy"
    else
        echo "❌ Unhealthy"
    fi
    
    # Get target group health
    echo ""
    echo "🎯 Target Group Health"
    echo "---------------------"
    
    # Get all target groups for this ALB
    TARGET_GROUPS=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?contains(LoadBalancerArns[0], 'anagram-$ENVIRONMENT')].{Name:TargetGroupName,Arn:TargetGroupArn,Port:Port}" \
        --output json)
    
    echo "$TARGET_GROUPS" | jq -r '.[] | "\(.Name) (port \(.Port))"' | while read -r tg_info; do
        TG_ARN=$(echo "$TARGET_GROUPS" | jq -r ".[] | select(.Name == \"$(echo "$tg_info" | cut -d' ' -f1)\") | .Arn")
        
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
            --output text)
        
        TOTAL_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --region "$REGION" \
            --query 'TargetHealthDescriptions | length(@)' \
            --output text)
        
        if [[ "$HEALTHY_COUNT" == "$TOTAL_COUNT" && "$TOTAL_COUNT" -gt 0 ]]; then
            echo "✅ $tg_info: $HEALTHY_COUNT/$TOTAL_COUNT healthy"
        else
            echo "⚠️  $tg_info: $HEALTHY_COUNT/$TOTAL_COUNT healthy"
        fi
    done
    
else
    echo "❌ Load Balancer not found"
fi

echo ""
echo "💾 Database Status"
echo "-----------------"

# Check Aurora cluster
DB_CLUSTER_ID="anagramstagingstack-anagramdatabase"
if [[ "$ENVIRONMENT" == "production" ]]; then
    DB_CLUSTER_ID="anagramproductionstack-anagramdatabase"
fi

DB_STATUS=$(aws rds describe-db-clusters \
    --region "$REGION" \
    --query "DBClusters[?contains(DBClusterIdentifier, '$DB_CLUSTER_ID')].Status" \
    --output text 2>/dev/null)

if [[ "$DB_STATUS" == "available" ]]; then
    echo "✅ Aurora database: Available"
else
    echo "⚠️  Aurora database: $DB_STATUS"
fi

echo ""
echo "🏁 Summary"
echo "---------"
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
if [[ -n "$ALB_DNS" ]]; then
    echo "Game API: http://$ALB_DNS/api/status"
fi
echo ""
echo "💡 To check logs:"
echo "   aws logs tail /ecs/anagram-$ENVIRONMENT-game-server --region $REGION --follow"
echo ""
echo "💡 To force service update:"
echo "   aws ecs update-service --cluster $CLUSTER_NAME --service anagram-$ENVIRONMENT-game-server --force-new-deployment --region $REGION"