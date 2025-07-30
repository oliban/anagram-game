#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { AnagramStack } from '../lib/anagram-stack';

const app = new cdk.App();

// Get environment from context
const environment = app.node.tryGetContext('environment') || 'staging';

if (environment === 'staging') {
  new AnagramStack(app, 'AnagramStagingStack', {
    environment: 'staging',
    env: { 
      account: process.env.CDK_DEFAULT_ACCOUNT, 
      region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
    },
  });
} else if (environment === 'production') {
  new AnagramStack(app, 'AnagramProductionStack', {
    environment: 'production',
    env: { 
      account: process.env.CDK_DEFAULT_ACCOUNT, 
      region: process.env.CDK_DEFAULT_REGION || 'eu-west-1'
    },
  });
} else {
  throw new Error(`Unknown environment: ${environment}. Use 'staging' or 'production'`);
}