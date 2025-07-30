# GitHub Actions CI/CD Setup

This directory contains GitHub Actions workflows for automated testing and deployment of the Anagram Game infrastructure.

## Workflows

### 1. `test.yml` - Continuous Integration
- **Triggers**: Push to `main`/`staging` branches, pull requests
- **Purpose**: Run tests for both backend services and iOS app
- **Jobs**:
  - `test-services`: Tests Node.js microservices with PostgreSQL
  - `test-ios`: Builds and tests iOS app on macOS runner

### 2. `deploy.yml` - Continuous Deployment
- **Triggers**: Push to `main`/`staging` branches, manual dispatch
- **Purpose**: Build Docker images, deploy to AWS ECS via CDK
- **Environment mapping**:
  - `main` branch → Production environment
  - `staging` branch → Staging environment

## Required GitHub Secrets

You must configure these secrets in your GitHub repository settings:

### AWS Credentials
```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=abc123...
```

These should be from an IAM user with the following permissions:
- `AmazonEC2ContainerRegistryFullAccess` (for ECR)
- `AWSCloudFormationFullAccess` (for CDK deployments)
- `AmazonECS_FullAccess` (for ECS services)
- `AmazonVPCFullAccess` (for networking)
- `AmazonRDSFullAccess` (for Aurora database)
- `ElasticLoadBalancingFullAccess` (for ALB)
- `IAMFullAccess` (for creating service roles)
- `CloudWatchLogsFullAccess` (for logging)

## Setup Instructions

1. **Configure Repository Secrets**:
   - Go to your GitHub repository
   - Navigate to Settings → Secrets and variables → Actions
   - Add the required AWS credentials as repository secrets

2. **Test the Workflows**:
   ```bash
   # Push to staging branch to test staging deployment
   git checkout -b staging
   git push origin staging
   
   # Push to main branch for production deployment
   git checkout main
   git push origin main
   ```

3. **Monitor Deployments**:
   - Check the Actions tab in your GitHub repository
   - View deployment logs and status
   - Get the deployed URLs from the deployment output

## Deployment Process

1. **Test Phase**: Runs unit tests and builds
2. **Build Phase**: Creates Docker images for all three services
3. **Push Phase**: Uploads images to AWS ECR
4. **Deploy Phase**: Uses CDK to update infrastructure
5. **Update Phase**: Forces ECS services to use new images
6. **Verify Phase**: Runs health checks on deployed services

## Troubleshooting

### Common Issues

1. **ECR Login Failed**: Check AWS credentials and ECR permissions
2. **CDK Deploy Failed**: Verify CloudFormation permissions
3. **Health Check Failed**: Check container health and security groups
4. **Service Update Timeout**: Increase health check grace period

### Debugging Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster anagram-staging --services anagram-staging-game-server

# View CloudFormation stack events
aws cloudformation describe-stack-events --stack-name AnagramStagingStack

# Check ECR repositories
aws ecr describe-repositories --query 'repositories[?contains(repositoryName, `anagram`)]'
```

## Environment Variables

The workflows automatically set these based on the git branch:

| Branch | Environment | Stack Name |
|--------|-------------|------------|
| `staging` | staging | AnagramStagingStack |
| `main` | production | AnagramProductionStack |

## Manual Deployment

You can also trigger deployments manually:

1. Go to Actions tab in GitHub
2. Select "Deploy to AWS" workflow
3. Click "Run workflow"
4. Choose the branch (main for production, staging for staging)