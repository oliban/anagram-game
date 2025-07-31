# AWS Production Server Management

## Quick Health Check
```bash
# Check if AWS production servers are online
curl -v http://anagram-staging-alb-1354034851.eu-west-1.elb.amazonaws.com/api/status

# Expected responses:
# ✅ 200 OK with JSON status - Servers are healthy
# ❌ 503 Service Unavailable - Load balancer online, but ECS services down
# ❌ Connection timeout/refused - Infrastructure is completely down
```

## Starting AWS Production Servers

### Option 1: AWS Console (Recommended for Quick Start)
1. **Login**: Go to AWS Console → ECS
2. **Navigate**: eu-west-1 region → Clusters → anagram-game-cluster
3. **Services**: Click on each service (game-server, web-dashboard, link-generator, admin-service)
4. **Scale Up**: Update service → Set desired count from 0 to 1
5. **Wait**: 2-5 minutes for tasks to reach RUNNING state
6. **Verify**: Check health endpoint again

### Option 2: AWS CLI (Automated)
```bash
# Scale up all ECS services
aws ecs update-service --cluster anagram-game-cluster --service anagram-game-server --desired-count 1
aws ecs update-service --cluster anagram-game-cluster --service anagram-web-dashboard --desired-count 1  
aws ecs update-service --cluster anagram-game-cluster --service anagram-link-generator --desired-count 1
aws ecs update-service --cluster anagram-game-cluster --service anagram-admin-service --desired-count 1

# Check service status
aws ecs describe-services --cluster anagram-game-cluster --services anagram-game-server anagram-web-dashboard anagram-link-generator anagram-admin-service

# Monitor deployment
aws ecs wait services-stable --cluster anagram-game-cluster --services anagram-game-server
```

### Option 3: Infrastructure as Code (Full Deployment)
```bash
# If using CDK for infrastructure management
cd aws-infrastructure/
cdk deploy --all --require-approval never

# If using Terraform
cd terraform/
terraform plan
terraform apply -auto-approve
```

## Stopping AWS Production Servers (Cost Optimization)
```bash
# Scale down to zero to stop costs
aws ecs update-service --cluster anagram-game-cluster --service anagram-game-server --desired-count 0
aws ecs update-service --cluster anagram-game-cluster --service anagram-web-dashboard --desired-count 0
aws ecs update-service --cluster anagram-game-cluster --service anagram-link-generator --desired-count 0
aws ecs update-service --cluster anagram-game-cluster --service anagram-admin-service --desired-count 0
```

## Monitoring AWS Production
```bash
# View real-time logs
aws logs tail /ecs/anagram-game-server --follow
aws logs tail /ecs/anagram-web-dashboard --follow
aws logs tail /ecs/anagram-link-generator --follow
aws logs tail /ecs/anagram-admin-service --follow

# Check task health
aws ecs describe-tasks --cluster anagram-game-cluster --tasks $(aws ecs list-tasks --cluster anagram-game-cluster --query 'taskArns[0]' --output text)
```

## Common AWS Issues & Solutions
- **503 Service Unavailable**: ECS tasks stopped → Scale services back up
- **Connection Timeouts**: Security groups blocking traffic → Check ALB security groups allow HTTP
- **Image Pull Errors**: Wrong platform architecture → Rebuild with `--platform linux/amd64`
- **Database Connection Issues**: Aurora Serverless sleeping → Make a query to wake it up

## Enhanced Build Workflow with Server Health Checks

The `build_and_test.sh` script provides an automated workflow that:

### Pre-Build Health Checks
- ✅ **Local Environment**: Checks if Docker services are running at `192.168.1.133:3000`
- ✅ **AWS Environment**: Verifies AWS production server availability
- ✅ **Auto-Start**: Offers to start local Docker services if needed
- ✅ **Clear Guidance**: Shows specific startup instructions when servers are down

### Usage
```bash
# Enhanced build with server health checks
./build_and_test.sh local              # Local development with health checks
./build_and_test.sh aws                # AWS production with health checks
./build_and_test.sh local --clean      # Clean build with health checks
```

### Workflow Features
1. **Pre-build server health verification**
2. **Automatic local service startup (with permission)**
3. **AWS server status validation**
4. **Post-build server log monitoring**
5. **Clear next-step guidance**

This workflow ensures you never build apps against non-functional servers and provides immediate feedback on server status and required actions.

## Microservices Architecture

The system now uses a 4-service microservices architecture:

### Service Responsibilities
- **🎮 Game Server (3000)**: Core multiplayer API, WebSocket connections, player management
- **📊 Web Dashboard (3001)**: Monitoring interface, system statistics, contribution management  
- **🔗 Link Generator (3002)**: Contribution link generation and management
- **🔧 Admin Service (3003)**: Content management, batch phrase imports, administrative operations
- **🗄️ PostgreSQL Database**: Shared data store for all services

### Service Health Endpoints
```bash
# Local Development
curl http://localhost:3000/api/status  # Game server
curl http://localhost:3001/api/status  # Web dashboard
curl http://localhost:3002/api/status  # Link generator  
curl http://localhost:3003/api/status  # Admin service

# AWS Production (replace with your ALB endpoint)
curl http://your-alb-endpoint.com/api/status      # Game server
curl http://your-alb-endpoint.com:3001/api/status # Web dashboard
curl http://your-alb-endpoint.com:3002/api/status # Link generator
curl http://your-alb-endpoint.com:3003/api/status # Admin service
```

### Admin Service Usage
The Admin Service provides content management capabilities:

```bash
# Batch import phrases (local)
curl -X POST http://localhost:3003/api/admin/phrases/batch-import \
  -H "Content-Type: application/json" \
  -d '{
    "phrases": [
      {
        "content": "example phrase",
        "hint": "A sample phrase",
        "language": "en"
      }
    ],
    "adminId": "admin-user"
  }'
```

This separation ensures clean architectural boundaries and allows independent scaling of different service types.