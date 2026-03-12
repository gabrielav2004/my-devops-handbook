# CI/CD Pipeline Architecture Evolution

> **Author**: DevOps Engineer  
> **Date**: December 2025  
> **Purpose**: Learning reference for deployment pipeline design decisions

---

## Table of Contents

1. [Overview](#overview)
2. [The Problem](#the-problem)
3. [Architecture Evolution](#architecture-evolution)
4. [Iteration 1: Webhook-Based Deployment](#iteration-1-webhook-based-deployment)
5. [Iteration 2: VPN + SSH Direct Deployment](#iteration-2-vpn--ssh-direct-deployment)
6. [Iteration 3: Dynamic Security Group (Considered)](#iteration-3-dynamic-security-group-considered)
7. [Key Learnings](#key-learnings)
8. [Final Recommendation](#final-recommendation)
9. [References](#references)

---

## Overview

This document chronicles the evolution of a CI/CD deployment pipeline from an over-engineered webhook-based system to a simple, secure VPN + SSH solution. The journey highlights important lessons about complexity, security tradeoffs, and knowing when to simplify.

**Key Takeaway**: Sometimes the best engineering decision is recognizing when to throw away work and simplify.

---

## The Problem

**Initial Context:**
- Small development team (2-5 people)
- Multiple microservices/applications to deploy
- GitHub Actions for CI/CD
- Need for automated deployments
- Private deployment servers

**Requirements:**
- Automated deployments triggered by GitHub Actions
- Support for multiple workflows per repository
- Environment-based deployments (production, staging, development)
- Secure communication between CI and deployment servers
- Real-time visibility into deployment status

**Initial Constraints:**
- GitHub Actions runners on public internet
- Deployment targets in private networks
- Need for secure, authenticated deployments
- Small team with limited operational overhead capacity

---

## Architecture Evolution

### Timeline

```
Week 1-2: Webhook + Flask Server
Week 3:   Simplified to VPN + SSH
Week 3:   Considered Dynamic SG approach (rejected)
```

---

## Iteration 1: Webhook-Based Deployment

### Architecture Diagram

```
┌─────────────────┐
│  GitHub Actions │
│   (CI Pipeline) │
└────────┬────────┘
         │ HTTP POST
         │ (Webhook)
         ▼
┌─────────────────────────────┐
│   GitHub Webhook Event      │
│  - workflow_run completed   │
│  - Payload with metadata    │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│    Flask Webhook Server     │
│  - Signature verification   │
│  - Multi-workflow routing   │
│  - Deployment orchestration │
│  - Metrics tracking         │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│   Deployment Scripts        │
│  - Docker image pull        │
│  - Container restart        │
│  - Health checks            │
└─────────────────────────────┘
```

### Flask Webhook Server Implementation

**File: `webhook_server.py`**

```python
import os
import hmac
import hashlib
import subprocess
import logging
import json
from datetime import datetime
from threading import Thread
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET')
DEPLOY_SCRIPTS_DIR = '/opt/deploy-scripts'

# Multi-workflow configuration
WORKFLOW_CONFIG = {
    'api-service': {
        'build-and-push': {
            'branches': {
                'main': {
                    'environment': 'production',
                    'deploy_script': 'api-service-deploy.sh'
                },
                'staging': {
                    'environment': 'staging',
                    'deploy_script': 'api-service-deploy.sh'
                }
            }
        },
        'build-worker': {
            'branches': {
                'main': {
                    'environment': 'production',
                    'deploy_script': 'api-worker-deploy.sh'
                }
            }
        }
    }
}

def verify_github_signature(payload_body, signature_header):
    """Verify GitHub webhook signature using HMAC SHA256"""
    if not signature_header:
        return False
    
    hash_object = hmac.new(
        WEBHOOK_SECRET.encode('utf-8'),
        msg=payload_body,
        digestmod=hashlib.sha256
    )
    expected_signature = "sha256=" + hash_object.hexdigest()
    return hmac.compare_digest(expected_signature, signature_header)

def run_deployment(repo_name, environment, deploy_script, run_number, commit_sha):
    """Execute deployment script in background thread"""
    try:
        script_path = os.path.join(DEPLOY_SCRIPTS_DIR, deploy_script)
        
        env = os.environ.copy()
        env.update({
            'REPO_NAME': repo_name,
            'ENVIRONMENT': environment,
            'RUN_NUMBER': str(run_number),
            'COMMIT_SHA': commit_sha
        })
        
        result = subprocess.run(
            ['bash', script_path],
            env=env,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        if result.returncode == 0:
            logging.info(f"✅ Deployment successful for {repo_name}")
        else:
            logging.error(f"❌ Deployment failed: {result.stderr}")
            
    except Exception as e:
        logging.error(f"Deployment error: {str(e)}")

@app.route('/webhook', methods=['POST'])
def github_webhook():
    """Handle GitHub webhook events"""
    
    # Verify signature
    signature = request.headers.get('X-Hub-Signature-256')
    if not verify_github_signature(request.data, signature):
        return jsonify({'error': 'Invalid signature'}), 403
    
    payload = request.json
    event_type = request.headers.get('X-GitHub-Event')
    
    # Only handle workflow_run events
    if event_type != 'workflow_run':
        return jsonify({'message': 'Event type not supported'}), 200
    
    # Only process completed workflows
    if payload.get('action') != 'completed':
        return jsonify({'message': 'Ignoring non-completed workflow'}), 200
    
    workflow_run = payload.get('workflow_run', {})
    repo_name = payload.get('repository', {}).get('name')
    workflow_name = workflow_run.get('name')
    branch = workflow_run.get('head_branch')
    conclusion = workflow_run.get('conclusion')
    run_number = workflow_run.get('run_number')
    commit_sha = workflow_run.get('head_sha')
    
    # Only deploy successful workflows
    if conclusion != 'success':
        return jsonify({'message': f'Not deploying, conclusion: {conclusion}'}), 200
    
    # Check workflow configuration
    if repo_name not in WORKFLOW_CONFIG:
        return jsonify({'message': 'Repository not configured'}), 200
    
    if workflow_name not in WORKFLOW_CONFIG[repo_name]:
        return jsonify({'message': 'Workflow not configured'}), 200
    
    workflow = WORKFLOW_CONFIG[repo_name][workflow_name]
    
    if branch not in workflow['branches']:
        return jsonify({'message': 'Branch not configured'}), 200
    
    config = workflow['branches'][branch]
    environment = config['environment']
    deploy_script = config['deploy_script']
    
    # Trigger deployment in background
    deployment_id = f"{repo_name}-{environment}-{run_number}"
    thread = Thread(
        target=run_deployment,
        args=(repo_name, environment, deploy_script, run_number, commit_sha)
    )
    thread.daemon = True
    thread.start()
    
    return jsonify({
        'status': 'accepted',
        'deployment_id': deployment_id,
        'environment': environment
    }), 202

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

### Deployment Script

**File: `/opt/deploy-scripts/api-service-deploy.sh`**

```bash
#!/bin/bash
set -euo pipefail

# Environment variables from Flask:
# - REPO_NAME
# - ENVIRONMENT
# - RUN_NUMBER
# - COMMIT_SHA

IMAGE_TAG="${RUN_NUMBER}"
IMAGE_NAME="myregistry/${REPO_NAME}:${IMAGE_TAG}"

echo "========================================"
echo "🚀 Starting deployment"
echo "========================================"
echo "Repository: $REPO_NAME"
echo "Environment: $ENVIRONMENT"
echo "Image: $IMAGE_NAME"
echo "Commit: $COMMIT_SHA"
echo "========================================"

# Pull latest image
docker pull "${IMAGE_NAME}"

# Deploy based on environment
if [ "$ENVIRONMENT" = "production" ]; then
    # Production: Docker Swarm
    docker service update \
        --image "${IMAGE_NAME}" \
        "${REPO_NAME}_prod"
else
    # Dev/Staging: Docker Compose
    docker-compose -f "docker-compose.${ENVIRONMENT}.yml" up -d
fi

# Health check
sleep 5
if curl -sf http://localhost:8080/health > /dev/null; then
    echo "✅ Health check passed"
    exit 0
else
    echo "❌ Health check failed, rolling back"
    docker service rollback "${REPO_NAME}_${ENVIRONMENT}"
    exit 1
fi
```

### GitHub Webhook Setup

**In GitHub Repository Settings:**

1. Navigate to: `Settings → Webhooks → Add webhook`
2. Configure:
   ```
   Payload URL: https://your-server.com/webhook
   Content type: application/json
   Secret: <generate-strong-secret>
   Events: ☑️ Workflow runs only
   Active: ☑️
   ```

### Problems with This Approach

#### 1. Over-Complexity
- Multiple services to maintain (Flask, systemd, deployment scripts)
- Complex debugging: "Is Flask down? Is the webhook not firing? Script failure?"
- High cognitive overhead for team onboarding

#### 2. Security Concerns
- **Exposed webhook endpoint** on public internet
- Required custom HMAC signature verification
- IP allowlisting management
- Secret rotation burden
- Any vulnerability in Flask exposes deployment infrastructure

#### 3. Operational Burden
- Flask server requires:
  - Monitoring (is it running?)
  - Updates (security patches)
  - Scaling (if traffic increases)
  - Log rotation
  - Systemd service management

#### 4. Development Time Sink
- Days spent on infrastructure instead of features
- Custom routing logic to maintain
- Webhook payload parsing complexity

### What Worked Well

✅ Multi-workflow configuration pattern (reusable concept)  
✅ Understanding of webhook security (HMAC verification)  
✅ Deployment script patterns (still used in final solution)  
✅ Environment-based deployment logic  

### Rating: 4.8/10

| Aspect | Rating |
|--------|--------|
| **Simplicity** | 2/10 |
| **Security** | 6/10 |
| **Reliability** | 5/10 |
| **Maintenance** | 3/10 |
| **Production Value** | 5/10 |

---

## Iteration 2: VPN + SSH Direct Deployment

### Architecture Diagram

```
┌─────────────────────────────┐
│     GitHub Actions          │
│   (CI + CD Pipeline)        │
└────────┬────────────────────┘
         │
         │ 1. Build & Push Image
         │
         ▼
┌─────────────────────────────┐
│   Container Registry        │
│   (Docker Hub / ECR / GCR)  │
└─────────────────────────────┘
         
         ┌──────────────────────┐
         │  2. Connect OpenVPN  │
         └────────┬─────────────┘
                  │
                  ▼
         ┌──────────────────────┐
         │   VPN Tunnel         │
         │  (Encrypted)         │
         └────────┬─────────────┘
                  │
                  │ 3. SSH to Server
                  │
                  ▼
         ┌──────────────────────┐
         │  Deployment Server   │
         │  (Private Network)   │
         │                      │
         │  - Pull image        │
         │  - Restart container │
         │  - Health check      │
         └──────────────────────┘
```

### GitHub Actions Workflow

**File: `.github/workflows/deploy.yml`**

```yaml
name: Build and Deploy

on:
  push:
    branches:
      - main
      - develop

env:
  IMAGE_NAME: myapp
  REGISTRY: docker.io/myorg

jobs:
  build-and-deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      
      - name: Determine environment
        id: env
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            echo "environment=production" >> $GITHUB_OUTPUT
          elif [ "${{ github.ref }}" = "refs/heads/develop" ]; then
            echo "environment=development" >> $GITHUB_OUTPUT
          else
            echo "environment=staging" >> $GITHUB_OUTPUT
          fi
      
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.run_number }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.env.outputs.environment }}-latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
      
      - name: Connect to VPN
        uses: kota65535/github-openvpn-connect-action@v2
        with:
          config_file: .github/vpn/client.ovpn
          username: ${{ secrets.VPN_USERNAME }}
          password: ${{ secrets.VPN_PASSWORD }}
          client_key: ${{ secrets.VPN_CLIENT_KEY }}
      
      - name: Wait for VPN connection
        run: |
          echo "Waiting for VPN to establish..."
          sleep 10
          ping -c 3 ${{ secrets.SERVER_PRIVATE_IP }}
      
      - name: Deploy to server via SSH
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_PRIVATE_IP }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: 22
          script: |
            set -e
            
            ENVIRONMENT="${{ steps.env.outputs.environment }}"
            IMAGE_TAG="${{ github.run_number }}"
            IMAGE_NAME="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${IMAGE_TAG}"
            
            echo "🚀 Starting deployment"
            echo "Environment: $ENVIRONMENT"
            echo "Image: $IMAGE_NAME"
            
            # Pull latest image
            docker pull "$IMAGE_NAME"
            
            # Deploy
            cd /opt/apps/myapp
            
            if [ "$ENVIRONMENT" = "production" ]; then
              docker service update --image "$IMAGE_NAME" myapp_prod
            else
              export IMAGE_TAG
              docker-compose -f docker-compose.${ENVIRONMENT}.yml up -d
            fi
            
            # Health check
            echo "⏳ Waiting for health check..."
            sleep 10
            
            if curl -sf http://localhost:8080/health > /dev/null; then
              echo "✅ Deployment successful!"
            else
              echo "❌ Health check failed!"
              exit 1
            fi
            
            # Cleanup
            docker image prune -f
      
      - name: Deployment status
        if: always()
        run: |
          if [ "${{ job.status }}" = "success" ]; then
            echo "✅ Deployment completed successfully"
          else
            echo "❌ Deployment failed"
            exit 1
          fi
```

### OpenVPN Server Setup

```bash
# Install OpenVPN on deployment server
sudo apt update
sudo apt install openvpn easy-rsa -y

# Initialize PKI
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Generate certificates
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1

# Configure OpenVPN server
sudo tee /etc/openvpn/server.conf > /dev/null <<EOF
port 1194
proto udp
dev tun
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh.pem
server 10.8.0.0 255.255.255.0
push "route 10.0.0.0 255.255.0.0"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
verb 3
EOF

# Start OpenVPN
sudo systemctl enable openvpn@server
sudo systemctl start openvpn@server
```

### OpenVPN Client Config

**File: `.github/vpn/client.ovpn`**

```
client
dev tun
proto udp
remote vpn.yourserver.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

<ca>
-----BEGIN CERTIFICATE-----
... CA certificate ...
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
... Client certificate ...
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
... Client private key ...
-----END PRIVATE KEY-----
</key>
```

### Why This Approach is Better

#### 1. Simplicity
- **3 components** instead of 8+
- GitHub Actions → VPN → SSH → Deploy
- All logs visible in GitHub Actions UI
- No custom code to maintain

#### 2. Security
- **VPN tunnel** encrypts all traffic end-to-end
- **SSH key authentication** (no passwords)
- **Private network** - no public exposure
- **Defense in depth**: VPN + SSH keys (2 independent layers)

#### 3. Reliability
- **Fewer failure points**: Less can break
- **Standard tools**: OpenVPN and SSH are battle-tested
- **Easy debugging**: Check GitHub Actions logs

#### 4. Operational Simplicity
- No Flask server to monitor
- OpenVPN is set-and-forget
- SSH is already on every server
- Standard sysadmin tools

#### 5. Observability
- **GitHub Actions shows all logs** - no separate log aggregation needed
- 90-day retention in GHA (sufficient for most needs)
- Can still add external observability later if needed

### Required GitHub Secrets

```
REGISTRY_USERNAME       # Docker registry username
REGISTRY_PASSWORD       # Docker registry password/token
VPN_USERNAME            # OpenVPN username
VPN_PASSWORD            # OpenVPN password
VPN_CLIENT_KEY          # OpenVPN client key (if using key auth)
SERVER_PRIVATE_IP       # Private IP of server (accessible via VPN)
SERVER_USER             # SSH username (e.g., ubuntu, deploy)
SSH_PRIVATE_KEY         # SSH private key for authentication
```

### Rating: 8.9/10

| Aspect | Rating |
|--------|--------|
| **Simplicity** | 10/10 |
| **Security** | 10/10 |
| **Reliability** | 9/10 |
| **Maintenance** | 10/10 |
| **Observability** | 7/10 |
| **Production Value** | 10/10 |

---

## Iteration 3: Dynamic Security Group (Considered)

### Architecture Diagram

```
┌─────────────────────────────┐
│     GitHub Actions          │
└────────┬────────────────────┘
         │
         │ 1. Get Runner IP
         │
         ▼
┌─────────────────────────────┐
│   AWS API (EC2)             │
│  - Whitelist runner IP      │
│  - Port 22, TCP             │
└────────┬────────────────────┘
         │
         │ 2. SSH (temporarily allowed)
         │
         ▼
┌─────────────────────────────┐
│  Deployment Server          │
│  (Public SSH temporarily)   │
└────────┬────────────────────┘
         │
         │ 3. Revoke IP
         │
         ▼
┌─────────────────────────────┐
│   AWS API (EC2)             │
│  - Remove IP from SG        │
└─────────────────────────────┘
```

### Implementation

**File: `.github/workflows/deploy-dynamic-sg.yml`**

```yaml
name: Deploy with Dynamic SG

on:
  push:
    branches:
      - main

env:
  SERVER_SG_ID: ${{ secrets.SERVER_SG_ID }}
  AWS_REGION: us-east-1

jobs:
  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials (OIDC - Recommended)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Get runner IP
        id: ip
        uses: haythem/public-ip@v1.2
      
      - name: Whitelist runner IP
        run: |
          aws ec2 authorize-security-group-ingress \
            --group-id $SERVER_SG_ID \
            --ip-permissions '[{
              "FromPort": 22,
              "ToPort": 22,
              "IpProtocol": "tcp",
              "IpRanges": [{
                "CidrIp": "${{ steps.ip.outputs.ipv4 }}/32",
                "Description": "GHA-${{ github.run_id }}-$(date -u +%Y-%m-%dT%H:%M:%SZ)"
              }]
            }]' || true
      
      - name: Wait for security group update
        run: sleep 5
      
      - name: Deploy via SSH
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_PUBLIC_IP }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /opt/apps/myapp
            docker pull myapp:${{ github.run_number }}
            docker-compose up -d
      
      - name: Revoke runner IP
        if: always()
        run: |
          aws ec2 revoke-security-group-ingress \
            --group-id $SERVER_SG_ID \
            --protocol tcp \
            --port 22 \
            --cidr ${{ steps.ip.outputs.ipv4 }}/32 || true
```

### Lambda Cleanup (Safety Net)

**File: `lambda/cleanup-stale-sg-rules.py`**

```python
import boto3
from datetime import datetime, timezone, timedelta
import re

def lambda_handler(event, context):
    """Cleanup stale security group rules older than 10 minutes"""
    ec2 = boto3.client('ec2')
    sg_id = 'sg-xxxxxxxxx'
    
    response = ec2.describe_security_groups(GroupIds=[sg_id])
    sg = response['SecurityGroups'][0]
    
    removed_count = 0
    
    for rule in sg.get('IpPermissions', []):
        if rule.get('FromPort') != 22:
            continue
        
        for ip_range in rule.get('IpRanges', []):
            description = ip_range.get('Description', '')
            
            if not description.startswith('GHA-'):
                continue
            
            try:
                timestamp_match = re.search(
                    r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)', 
                    description
                )
                
                if timestamp_match:
                    timestamp_str = timestamp_match.group(1)
                    rule_time = datetime.strptime(
                        timestamp_str, 
                        '%Y-%m-%dT%H:%M:%SZ'
                    ).replace(tzinfo=timezone.utc)
                    
                    age = datetime.now(timezone.utc) - rule_time
                    
                    if age > timedelta(minutes=10):
                        ec2.revoke_security_group_ingress(
                            GroupId=sg_id,
                            IpPermissions=[{
                                'FromPort': 22,
                                'ToPort': 22,
                                'IpProtocol': 'tcp',
                                'IpRanges': [{'CidrIp': ip_range['CidrIp']}]
                            }]
                        )
                        removed_count += 1
                        print(f"Removed: {ip_range['CidrIp']} (age: {age})")
                    
            except Exception as e:
                print(f"Error: {e}")
    
    return {'statusCode': 200, 'body': f'Removed {removed_count} rules'}
```

### Problems with This Approach

#### 1. Security Regression
- Port 22 exposed to public internet (even temporarily)
- 30-second window is enough for automated attacks
- No defense in depth

#### 2. Race Conditions
- Parallel workflows can fail with duplicate rule errors
- If runner crashes, revoke never runs
- Permanently open SSH until manual cleanup

#### 3. Added Complexity
- AWS credentials to manage
- Lambda function deployment
- EventBridge scheduling
- IAM policies
- More components than VPN

### When This Makes Sense

✅ You don't have/want VPN infrastructure  
✅ Cost is critical (no VPN server)  
✅ You use OIDC (not access keys)  
✅ You implement Lambda cleanup  
✅ You're comfortable with temporary public SSH  

### Rating: 6.7/10

| Aspect | Rating |
|--------|--------|
| **Simplicity** | 7/10 |
| **Security** | 5/10 |
| **Reliability** | 6/10 |
| **Maintenance** | 7/10 |
| **Production Value** | 6/10 |

---

## Key Learnings

### 1. Complexity is Not Sophistication

Building webhook infrastructure for a small team is over-engineering.

**Lesson:** Match architecture to actual scale, not what looks impressive.

### 2. Boring Technology Wins

VPN + SSH has been around for decades. It's boring, but that's why it works:
- Well-documented
- Battle-tested
- Everyone understands it
- Fewer surprises

**Lesson:** Use proven technology unless you have specific reasons not to.

### 3. The Best Code is No Code

Going from Flask server to SSH eliminated:
- 500+ lines of Python
- Multiple service dependencies
- Complex configuration
- Custom security implementations

**Lesson:** Code you don't write is code you don't maintain.

### 4. Sunk Cost Fallacy is Real

After spending days on webhooks, there was temptation to keep it just because of time invested.

**Lesson:** Don't let past investment prevent better decisions.

### 5. Security Through Simplicity

VPN + SSH keys is more secure than webhook signatures + IP allowlisting:
- Fewer attack surfaces
- Defense in depth
- No public endpoints

**Lesson:** Simpler solutions can be more secure.

### 6. OIDC Over Access Keys

For AWS integrations, use OIDC (temporary credentials) instead of long-lived keys.

### 7. Defense in Depth Matters

Single security layer (dynamic SG) is weaker than multiple layers (VPN + SSH).

### 8. Appropriate Technology for Scale

| Team Size | Repos | Deployments/Day | Solution |
|-----------|-------|-----------------|----------|
| 1-5 | 1-10 | <50 | VPN + SSH |
| 5-20 | 10-50 | 50-200 | Webhooks + Simple observability |
| 20+ | 50+ | 200+ | Full observability stack |

**Lesson:** Architecture should grow with actual needs.

---

## Final Recommendation

### For Small Teams (1-10 people, 1-20 repos): VPN + SSH

```
GitHub Actions → OpenVPN → SSH → Deploy
```

**Why:**
- ✅ 3 components total
- ✅ All logs in GitHub Actions UI
- ✅ Defense in depth (VPN + SSH)
- ✅ No public endpoints
- ✅ Minimal maintenance
- ✅ Battle-tested technology

### Implementation Checklist

**Server Setup:**
```bash
1. Install OpenVPN
2. Generate certificates
3. Start OpenVPN service
4. Configure SSH keys
5. Prepare deployment directories
```

**GitHub Setup:**
```bash
1. Add secrets (VPN, SSH, registry credentials)
2. Add OpenVPN config file
3. Create deployment workflow
4. Test deployment
```

### Comparison Matrix

| Aspect | Webhook | VPN + SSH | Dynamic SG |
|--------|---------|-----------|------------|
| **Components** | 8+ | 3 | 4 |
| **Setup Time** | 2-3 days | 2-3 hours | 1-2 hours |
| **Security** | Medium | High | Medium-Low |
| **Maintenance** | High | Low | Medium |
| **Best For** | Large teams | Small teams | No VPN |
| **Rating** | 4.8/10 | 8.9/10 | 6.7/10 |

---

## References

### GitHub Actions
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [appleboy/ssh-action](https://github.com/appleboy/ssh-action)
- [kota65535/github-openvpn-connect-action](https://github.com/kota65535/github-openvpn-connect-action)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)

### Security
- [GitHub Webhook Signature Verification](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries)
- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [SSH Key Authentication](https://www.ssh.com/academy/ssh/public-key-authentication)

### Tools
- [OpenVPN Documentation](https://openvpn.net/community-resources/)
- [Docker Documentation](https://docs.docker.com/)
- [Flask Documentation](https://flask.palletsprojects.com/)

---

## Conclusion

This journey demonstrates that the best solution is often not the most complex one. While building the webhook infrastructure was valuable learning, the VPN + SSH solution better matches the actual requirements of a small team.

**Key Takeaway:** Always question whether added complexity provides proportional value. The ability to recognize over-engineering and course-correct is a senior-level skill.

**Final thought:** Sometimes the best engineering decision is recognizing when to throw away work and simplify.
