import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import { Construct } from 'constructs';

export interface AnagramStackProps extends cdk.StackProps {
  environment: 'staging' | 'production';
}

export class AnagramStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AnagramStackProps) {
    super(scope, id, props);

    const { environment } = props;

    // VPC - Network foundation
    const vpc = new ec2.Vpc(this, 'AnagramVPC', {
      maxAzs: 2, // Use 2 AZs for high availability
      natGateways: 1, // Cost optimization - single NAT gateway
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 28,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // ECR Repositories for container images
    const gameServerRepo = new ecr.Repository(this, 'GameServerRepo', {
      repositoryName: `anagram-${environment}-game-server`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      imageScanOnPush: true,
    });

    const webDashboardRepo = new ecr.Repository(this, 'WebDashboardRepo', {
      repositoryName: `anagram-${environment}-web-dashboard`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      imageScanOnPush: true,
    });

    const linkGeneratorRepo = new ecr.Repository(this, 'LinkGeneratorRepo', {
      repositoryName: `anagram-${environment}-link-generator`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      imageScanOnPush: true,
    });

    // Database credentials secret
    const dbSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      secretName: `anagram-${environment}-db-credentials`,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ 
          username: 'postgres',
          port: 5432,
          dbname: 'anagram_game'
        }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        includeSpace: false,
        passwordLength: 32,
      },
    });

    // Aurora Serverless v2 Database
    const dbCluster = new rds.DatabaseCluster(this, 'AnagramDatabase', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_4,
      }),
      credentials: rds.Credentials.fromSecret(dbSecret),
      writer: rds.ClusterInstance.serverlessV2('writer', {
        scaleWithWriter: true,
      }),
      serverlessV2MinCapacity: 0.5, // Scale down to 0.5 ACU when idle
      serverlessV2MaxCapacity: environment === 'production' ? 16 : 4,
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      defaultDatabaseName: 'anagram_game',
      backup: {
        retention: cdk.Duration.days(environment === 'production' ? 7 : 1),
        preferredWindow: '03:00-04:00', // UTC
      },
      deletionProtection: environment === 'production',
      removalPolicy: environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });


    // ECS Cluster
    const ecsCluster = new ecs.Cluster(this, 'AnagramCluster', {
      vpc,
      clusterName: `anagram-${environment}`,
      containerInsights: true, // Enable CloudWatch Container Insights
    });

    // Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'AnagramALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: `anagram-${environment}-alb`,
    });

    // HTTP Listener (redirect to HTTPS in production)
    const httpListener = alb.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
    });

    if (environment === 'production') {
      // TODO: Add HTTPS listener with SSL certificate
      httpListener.addAction('HttpRedirect', {
        action: elbv2.ListenerAction.redirect({
          protocol: 'HTTPS',
          port: '443',
          permanent: true,
        }),
      });
    } else {
      // For staging, add a default action that returns 404 for unmatched paths
      httpListener.addAction('DefaultAction', {
        action: elbv2.ListenerAction.fixedResponse(404, {
          contentType: 'text/plain',
          messageBody: 'Not Found - Anagram Game API',
        }),
      });
    }

    // Log Groups
    const gameServerLogGroup = new logs.LogGroup(this, 'GameServerLogGroup', {
      logGroupName: `/ecs/anagram-${environment}-game-server`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const webDashboardLogGroup = new logs.LogGroup(this, 'WebDashboardLogGroup', {
      logGroupName: `/ecs/anagram-${environment}-web-dashboard`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const linkGeneratorLogGroup = new logs.LogGroup(this, 'LinkGeneratorLogGroup', {
      logGroupName: `/ecs/anagram-${environment}-link-generator`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Task Execution Role
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Grant access to read secrets
    dbSecret.grantRead(taskExecutionRole);

    // Task Role for services to access AWS resources
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    // Game Server Service
    const gameServerTaskDef = new ecs.FargateTaskDefinition(this, 'GameServerTaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    const gameServerContainer = gameServerTaskDef.addContainer('GameServerContainer', {
      image: ecs.ContainerImage.fromEcrRepository(gameServerRepo, 'latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'game-server',
        logGroup: gameServerLogGroup,
      }),
      environment: {
        NODE_ENV: environment,
        PORT: '3000',
        DB_HOST: dbCluster.clusterEndpoint.hostname,
        DB_PORT: '5432',
        DB_NAME: 'anagram_game',
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(dbSecret, 'password'),
        DB_USER: ecs.Secret.fromSecretsManager(dbSecret, 'username'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/api/status || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    gameServerContainer.addPortMappings({
      containerPort: 3000,
      protocol: ecs.Protocol.TCP,
    });

    const gameServerService = new ecs.FargateService(this, 'GameServerService', {
      cluster: ecsCluster,
      taskDefinition: gameServerTaskDef,
      serviceName: `anagram-${environment}-game-server`,
      desiredCount: environment === 'production' ? 2 : 1,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      healthCheckGracePeriod: cdk.Duration.seconds(120),
    });

    // Auto Scaling for Game Server
    const gameServerScaling = gameServerService.autoScaleTaskCount({
      minCapacity: 1,
      maxCapacity: environment === 'production' ? 10 : 3,
    });

    gameServerScaling.scaleOnCpuUtilization('GameServerCpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(2),
    });

    // Target Group for Game Server
    const gameServerTargetGroup = new elbv2.ApplicationTargetGroup(this, 'GameServerTargetGroup', {
      vpc,
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        path: '/api/status',
        protocol: elbv2.Protocol.HTTP,
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 5,
      },
    });

    gameServerService.attachToApplicationTargetGroup(gameServerTargetGroup);

    // Add listener rule for game server
    const gameServerListener = httpListener;
    gameServerListener.addAction('GameServerAction', {
      priority: 100,
      conditions: [
        elbv2.ListenerCondition.pathPatterns(['/api/*', '/socket.io/*']),
      ],
      action: elbv2.ListenerAction.forward([gameServerTargetGroup]),
    });

    // Web Dashboard Service (similar pattern)
    const webDashboardTaskDef = new ecs.FargateTaskDefinition(this, 'WebDashboardTaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    const webDashboardContainer = webDashboardTaskDef.addContainer('WebDashboardContainer', {
      image: ecs.ContainerImage.fromEcrRepository(webDashboardRepo, 'latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'web-dashboard',
        logGroup: webDashboardLogGroup,
      }),
      environment: {
        NODE_ENV: environment,
        WEB_DASHBOARD_PORT: '3001',
        DB_HOST: dbCluster.clusterEndpoint.hostname,
        DB_PORT: '5432',
        DB_NAME: 'anagram_game',
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(dbSecret, 'password'),
        DB_USER: ecs.Secret.fromSecretsManager(dbSecret, 'username'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3001/api/status || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    webDashboardContainer.addPortMappings({
      containerPort: 3001,
      protocol: ecs.Protocol.TCP,
    });

    const webDashboardService = new ecs.FargateService(this, 'WebDashboardService', {
      cluster: ecsCluster,
      taskDefinition: webDashboardTaskDef,
      serviceName: `anagram-${environment}-web-dashboard`,
      desiredCount: 1,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Target Group for Web Dashboard
    const webDashboardTargetGroup = new elbv2.ApplicationTargetGroup(this, 'WebDashboardTargetGroup', {
      vpc,
      port: 3001,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        path: '/api/status',
        protocol: elbv2.Protocol.HTTP,
      },
    });

    webDashboardService.attachToApplicationTargetGroup(webDashboardTargetGroup);

    // Add listener rule for web dashboard
    gameServerListener.addAction('WebDashboardAction', {
      priority: 200,
      conditions: [
        elbv2.ListenerCondition.pathPatterns(['/dashboard/*', '/admin/*']),
      ],
      action: elbv2.ListenerAction.forward([webDashboardTargetGroup]),
    });

    // Link Generator Service
    const linkGeneratorTaskDef = new ecs.FargateTaskDefinition(this, 'LinkGeneratorTaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
    });

    const linkGeneratorContainer = linkGeneratorTaskDef.addContainer('LinkGeneratorContainer', {
      image: ecs.ContainerImage.fromEcrRepository(linkGeneratorRepo, 'latest'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'link-generator',
        logGroup: linkGeneratorLogGroup,
      }),
      environment: {
        NODE_ENV: environment,
        LINK_GENERATOR_PORT: '3002',
        DB_HOST: dbCluster.clusterEndpoint.hostname,
        DB_PORT: '5432',
        DB_NAME: 'anagram_game',
      },
      secrets: {
        DB_PASSWORD: ecs.Secret.fromSecretsManager(dbSecret, 'password'),
        DB_USER: ecs.Secret.fromSecretsManager(dbSecret, 'username'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3002/api/status || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    linkGeneratorContainer.addPortMappings({
      containerPort: 3002,
      protocol: ecs.Protocol.TCP,
    });

    const linkGeneratorService = new ecs.FargateService(this, 'LinkGeneratorService', {
      cluster: ecsCluster,
      taskDefinition: linkGeneratorTaskDef,
      serviceName: `anagram-${environment}-link-generator`,
      desiredCount: 1,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Target Group for Link Generator
    const linkGeneratorTargetGroup = new elbv2.ApplicationTargetGroup(this, 'LinkGeneratorTargetGroup', {
      vpc,
      port: 3002,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        path: '/api/status',
        protocol: elbv2.Protocol.HTTP,
      },
    });

    linkGeneratorService.attachToApplicationTargetGroup(linkGeneratorTargetGroup);

    // Add listener rule for link generator
    gameServerListener.addAction('LinkGeneratorAction', {
      priority: 300,
      conditions: [
        elbv2.ListenerCondition.pathPatterns(['/contribute/*', '/link/*']),
      ],
      action: elbv2.ListenerAction.forward([linkGeneratorTargetGroup]),
    });

    // Security Groups
    dbCluster.connections.allowFrom(gameServerService, ec2.Port.tcp(5432), 'Game server to database');
    dbCluster.connections.allowFrom(webDashboardService, ec2.Port.tcp(5432), 'Web dashboard to database');
    dbCluster.connections.allowFrom(linkGeneratorService, ec2.Port.tcp(5432), 'Link generator to database');

    // Outputs
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `anagram-${environment}-alb-dns`,
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: dbCluster.clusterEndpoint.hostname,
      description: 'Aurora database cluster endpoint',
      exportName: `anagram-${environment}-db-endpoint`,
    });

    new cdk.CfnOutput(this, 'GameServerURL', {
      value: `http://${alb.loadBalancerDnsName}/api/status`,
      description: 'Game Server health check URL',
    });

    new cdk.CfnOutput(this, 'GameServerRepoURI', {
      value: gameServerRepo.repositoryUri,
      description: 'Game Server ECR Repository URI',
      exportName: `anagram-${environment}-game-server-repo`,
    });

    new cdk.CfnOutput(this, 'WebDashboardRepoURI', {
      value: webDashboardRepo.repositoryUri,
      description: 'Web Dashboard ECR Repository URI',
      exportName: `anagram-${environment}-web-dashboard-repo`,
    });

    new cdk.CfnOutput(this, 'LinkGeneratorRepoURI', {
      value: linkGeneratorRepo.repositoryUri,
      description: 'Link Generator ECR Repository URI',
      exportName: `anagram-${environment}-link-generator-repo`,
    });
  }
}