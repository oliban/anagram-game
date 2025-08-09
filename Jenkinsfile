#!/usr/bin/env groovy

/*
 * Jenkins Pipeline for Wordshelf API Testing
 * This pipeline runs comprehensive API tests as part of CI/CD
 */

pipeline {
    agent any
    
    environment {
        NODE_VERSION = '18'
        API_URL = 'http://localhost:3000'
        DOCKER_COMPOSE_FILE = 'docker-compose.services.yml'
        
        // Determine test configuration based on branch/trigger
        SKIP_PERFORMANCE = "${env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'develop' ? 'false' : 'true'}"
        STOP_ON_FAILURE = "${env.BRANCH_NAME == 'main' ? 'true' : 'false'}"
    }
    
    options {
        // Keep builds for 30 days, max 50 builds
        buildDiscarder(logRotator(numToKeepStr: '50', daysToKeepStr: '30'))
        
        // Timeout the entire pipeline after 20 minutes
        timeout(time: 20, unit: 'MINUTES')
        
        // Add timestamps to console output
        timestamps()
        
        // Clean workspace before build
        skipDefaultCheckout(false)
    }
    
    triggers {
        // Poll SCM every 5 minutes for changes (adjust as needed)
        pollSCM('H/5 * * * *')
        
        // Nightly builds at 2 AM
        cron(env.BRANCH_NAME == 'main' ? '0 2 * * *' : '')
        
        // Business hours health check (weekdays at 2 PM)
        cron(env.BRANCH_NAME == 'main' ? '0 14 * * 1-5' : '')
    }
    
    stages {
        stage('🔍 Environment Setup') {
            steps {
                echo "Setting up test environment for branch: ${env.BRANCH_NAME}"
                echo "Build trigger: ${env.BUILD_CAUSE}"
                echo "Skip Performance: ${env.SKIP_PERFORMANCE}"
                echo "Stop on Failure: ${env.STOP_ON_FAILURE}"
                
                // Clean up any previous test artifacts
                sh '''
                    rm -rf testing/reports/*
                    mkdir -p testing/reports
                '''
                
                // Install Node.js if not available
                script {
                    def nodeExists = sh(script: 'which node', returnStatus: true) == 0
                    if (!nodeExists) {
                        error "Node.js ${env.NODE_VERSION} not available. Please install Node.js on the Jenkins agent."
                    }
                }
                
                // Install dependencies
                sh '''
                    npm install
                    npm install socket.io-client
                '''
            }
        }
        
        stage('🐳 Service Startup') {
            steps {
                echo 'Starting Docker services for testing...'
                
                script {
                    try {
                        // Stop any existing services
                        sh """
                            docker-compose -f ${env.DOCKER_COMPOSE_FILE} down --remove-orphans || true
                        """
                        
                        // Start services with health checks
                        sh """
                            docker-compose -f ${env.DOCKER_COMPOSE_FILE} up -d --wait --wait-timeout 120
                        """
                        
                        // Additional health verification
                        sh '''
                            echo "Waiting for services to be fully ready..."
                            sleep 15
                            
                            # Health check all services
                            curl -f http://localhost:3000/api/status || (echo "Game Server health check failed" && exit 1)
                            curl -f http://localhost:3001/api/status || (echo "Web Dashboard health check failed" && exit 1)
                            curl -f http://localhost:3002/api/status || (echo "Link Generator health check failed" && exit 1)
                            curl -f http://localhost:3003/api/status || (echo "Admin Service health check failed" && exit 1)
                            
                            echo "✅ All services are healthy"
                        '''
                        
                    } catch (Exception e) {
                        echo "Failed to start services: ${e.getMessage()}"
                        
                        // Capture service logs for debugging
                        sh """
                            echo "=== Service Logs ==="
                            docker-compose -f ${env.DOCKER_COMPOSE_FILE} logs --tail=50
                        """
                        
                        throw e
                    }
                }
            }
        }
        
        stage('🧪 API Tests') {
            parallel {
                stage('Core API Tests') {
                    steps {
                        echo 'Running core API test suite...'
                        
                        script {
                            def testFlags = ""
                            
                            if (env.SKIP_PERFORMANCE == 'true') {
                                testFlags += "SKIP_PERFORMANCE=true "
                            }
                            
                            if (env.STOP_ON_FAILURE == 'true') {
                                testFlags += "--stop-on-failure "
                            }
                            
                            // Run the automated test suite
                            def testResult = sh(
                                script: "${testFlags}node testing/scripts/automated-test-runner.js ${testFlags}",
                                returnStatus: true
                            )
                            
                            // Store test result for later use
                            env.API_TEST_RESULT = testResult
                            
                            if (testResult != 0) {
                                echo "⚠️ API tests completed with issues (exit code: ${testResult})"
                                
                                // Don't fail immediately - let other stages complete for full reporting
                                if (env.STOP_ON_FAILURE == 'true') {
                                    error "Critical API test failure - stopping pipeline"
                                }
                            } else {
                                echo "✅ API tests completed successfully"
                            }
                        }
                    }
                    
                    post {
                        always {
                            // Archive test reports regardless of outcome
                            archiveArtifacts artifacts: 'testing/reports/**/*', 
                                           fingerprint: true,
                                           allowEmptyArchive: true
                        }
                    }
                }
                
                stage('Performance Tests') {
                    when {
                        anyOf {
                            branch 'main'
                            branch 'develop'
                            triggeredBy 'TimerTrigger'
                        }
                    }
                    
                    steps {
                        echo 'Running performance test suite...'
                        
                        script {
                            try {
                                sh '''
                                    echo "🏎️ Starting performance tests..."
                                    node testing/performance/test_performance_suite.js
                                '''
                                echo "✅ Performance tests completed successfully"
                                
                            } catch (Exception e) {
                                echo "⚠️ Performance tests failed: ${e.getMessage()}"
                                env.PERFORMANCE_TEST_RESULT = 'FAILED'
                                
                                // Performance failures are warnings, not hard failures
                                unstable("Performance tests failed")
                            }
                        }
                    }
                }
            }
        }
        
        stage('📊 Test Analysis') {
            steps {
                echo 'Analyzing test results...'
                
                script {
                    // Parse test results from reports
                    if (fileExists('testing/reports/latest-test-summary.md')) {
                        def summaryContent = readFile('testing/reports/latest-test-summary.md')
                        
                        // Extract key metrics
                        def successRateMatch = summaryContent =~ /Overall Success Rate.*?(\d+\.?\d*)%/
                        def suitesMatch = summaryContent =~ /Test Suites.*?(\d+)\/(\d+) passed/
                        
                        if (successRateMatch) {
                            env.OVERALL_SUCCESS_RATE = successRateMatch[0][1]
                        }
                        
                        if (suitesMatch) {
                            env.PASSED_SUITES = suitesMatch[0][1]
                            env.TOTAL_SUITES = suitesMatch[0][2]
                        }
                        
                        echo "📊 Test Results Summary:"
                        echo "Overall Success Rate: ${env.OVERALL_SUCCESS_RATE}%"
                        echo "Test Suites Passed: ${env.PASSED_SUITES}/${env.TOTAL_SUITES}"
                        
                        // Set build description
                        currentBuild.description = "API Tests: ${env.OVERALL_SUCCESS_RATE}% success rate"
                        
                    } else {
                        echo "⚠️ Test summary not found - check test execution"
                        env.OVERALL_SUCCESS_RATE = "0"
                    }
                }
            }
        }
        
        stage('🚀 Deployment Gate') {
            when {
                branch 'main'
            }
            
            steps {
                echo 'Evaluating deployment readiness...'
                
                script {
                    def successRate = Float.parseFloat(env.OVERALL_SUCCESS_RATE ?: "0")
                    def apiTestResult = Integer.parseInt(env.API_TEST_RESULT ?: "1")
                    
                    if (successRate >= 95.0 && apiTestResult == 0) {
                        echo "✅ DEPLOYMENT APPROVED: High success rate (${successRate}%)"
                        env.DEPLOYMENT_APPROVED = 'true'
                        
                        // In a real pipeline, trigger deployment here
                        echo "🚀 Would trigger deployment to staging/production"
                        
                    } else if (successRate >= 90.0) {
                        echo "⚠️ DEPLOYMENT CONDITIONAL: Moderate success rate (${successRate}%)"
                        echo "Manual approval may be required for deployment"
                        env.DEPLOYMENT_APPROVED = 'conditional'
                        
                    } else {
                        echo "❌ DEPLOYMENT BLOCKED: Low success rate (${successRate}%)"
                        env.DEPLOYMENT_APPROVED = 'false'
                        unstable("Test success rate below deployment threshold")
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo 'Pipeline cleanup...'
            
            // Stop Docker services
            sh """
                docker-compose -f ${env.DOCKER_COMPOSE_FILE} down --remove-orphans || true
            """
            
            // Publish test results if available
            script {
                if (fileExists('testing/reports/latest-test-summary.md')) {
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'testing/reports',
                        reportFiles: 'latest-test-summary.md',
                        reportName: 'API Test Report'
                    ])
                }
            }
            
            // Clean workspace
            cleanWs(
                deleteDirs: true,
                notFailBuild: true,
                patterns: [
                    [pattern: 'node_modules/**', type: 'EXCLUDE'],
                    [pattern: 'testing/reports/**', type: 'EXCLUDE']
                ]
            )
        }
        
        success {
            echo "✅ Pipeline completed successfully!"
            
            script {
                if (env.BRANCH_NAME == 'main') {
                    // Send success notification for main branch
                    echo "📢 Notifying team of successful main branch tests"
                    
                    // Example: Slack notification (requires Slack plugin)
                    // slackSend(
                    //     channel: '#api-tests',
                    //     color: 'good',
                    //     message: "✅ API Tests passed on main branch (${env.OVERALL_SUCCESS_RATE}% success rate)"
                    // )
                }
            }
        }
        
        failure {
            echo "❌ Pipeline failed!"
            
            script {
                // Send failure notifications
                echo "📢 Notifying team of test failures"
                
                // Example: Email notification (requires Email Extension plugin)
                // emailext(
                //     subject: "❌ API Tests Failed - ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                //     body: """
                //     API test pipeline failed for ${env.BRANCH_NAME}.
                    
                //     Build: ${env.BUILD_URL}
                //     Success Rate: ${env.OVERALL_SUCCESS_RATE}%
                    
                //     Please check the test reports for details.
                //     """,
                //     to: "${env.CHANGE_AUTHOR_EMAIL ?: 'team@example.com'}"
                // )
                
                // Example: Create JIRA ticket for main branch failures
                if (env.BRANCH_NAME == 'main') {
                    echo "Creating incident ticket for main branch failure"
                    // jiraCreateIssue(...)
                }
            }
        }
        
        unstable {
            echo "⚠️ Pipeline completed with warnings"
            
            // Send warning notifications for unstable builds
            echo "📢 Performance issues or test instability detected"
        }
    }
}