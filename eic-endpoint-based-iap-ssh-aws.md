# EC2 Instance Connect Endpoint (EICE) Setup

Connect to private EC2 instances without opening SSH to the internet.

---

## How It Works

```
Your machine
    │
    │ HTTPS (WebSocket) — IAM authenticated
    ▼
EICE Endpoint  (managed by AWS, inside your VPC)
    │
    │ Private TCP port 22
    ▼
EC2 Instance  (no public IP, no bastion needed)
```

- No public IP on EC2
- No SSH open to internet
- IAM controls who can connect
- Every connection logged in CloudTrail

---

## Prerequisites

- AWS CLI v2 installed
- An existing EC2 instance in a VPC
- IAM permissions to create EICE endpoint

---

## Step 1 — Create EICE Security Group

1. Go to **EC2 → Security Groups → Create security group**
2. Fill in:
   - Name: `eice-sg`
   - VPC: same VPC as your EC2 instance
3. **Inbound rules** — delete all (none needed)
4. **Outbound rules** — leave default (all traffic allowed)
5. Click **Create**

---

## Step 2 — Update EC2 Security Group

1. Go to **EC2 → Security Groups → select your existing EC2 SG**
2. Click **Inbound rules → Edit inbound rules**
3. Add rule:
   - Type: `SSH`
   - Port: `22`
   - Source: select `eice-sg` by ID
4. Click **Save rules**

> Port 22 is now only reachable from the EICE endpoint, not from the internet.

---

## Step 3 — Create the EICE Endpoint

1. Go to **EC2 → Network & Security → Instance Connect Endpoints → Create**
2. Fill in:
   - Name: `my-eice` (optional)
   - VPC: same VPC as your EC2 instance
   - Subnet: any subnet in that VPC
   - Security group: `eice-sg`
   - Preserve client IP: **enabled**
3. Click **Create endpoint**
4. Wait for status to show **Available** (takes 1-2 minutes)

---

## Step 4 — Connect

### Via Console

1. Go to **EC2 → Instances → select your instance → Connect**
2. Choose **EC2 Instance Connect** tab
3. Connection type: **Connect using EC2 Instance Connect Endpoint**
4. Select your endpoint
5. Click **Connect**

### Via AWS CLI

**Simplest (ephemeral key, no key file needed):**
```bash
aws ec2-instance-connect ssh \
  --instance-id i-xxxxxxxx \
  --connection-type eice \
  --os-user ubuntu \
  --region ap-south-1
```

**With your own key pair:**
```bash
ssh -i ~/.ssh/my-key.pem ubuntu@i-xxxxxxxx \
  -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id i-xxxxxxxx'
```

### Via ~/.ssh/config (recommended for daily use)

Add to `~/.ssh/config`:
```
Host my-ec2
  HostName i-xxxxxxxx
  User ubuntu
  IdentityFile ~/.ssh/my-key.pem
  ProxyCommand aws ec2-instance-connect open-tunnel --instance-id %h
```

Then just run:
```bash
ssh my-ec2
```

---

## Windows Notes

### WSL (recommended for work laptops)

Work laptops with Group Policy cause SSH key permission errors on Windows.
Use WSL to avoid this entirely.

**Install AWS CLI in WSL:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

**Copy key and fix permissions:**
```bash
cp /mnt/c/Users/<username>/.ssh/my-key.pem ~/.ssh/my-key.pem
chmod 400 ~/.ssh/my-key.pem
```

**Connect:**
```bash
aws ec2-instance-connect ssh \
  --instance-id i-xxxxxxxx \
  --connection-type eice \
  --os-user ubuntu \
  --private-key-file ~/.ssh/my-key.pem
```

---

## CI/CD Setup (GitHub Actions)

Uses `aws ec2-instance-connect ssh` with ephemeral keys — no SSH key management needed.

### Step 1 — Create IAM User for CI/CD

Create a dedicated IAM user (e.g. `cicd-deploy`) with only the following policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "OpenTunnel",
      "Effect": "Allow",
      "Action": "ec2-instance-connect:OpenTunnel",
      "Resource": "arn:aws:ec2:ap-south-1:123456789012:instance-connect-endpoint/eice-xxxxxxxx",
      "Condition": {
        "NumericLessThanEquals": {
          "ec2-instance-connect:maxTunnelDuration": "3600"
        }
      }
    },
    {
      "Sid": "SendSSHKey",
      "Effect": "Allow",
      "Action": "ec2-instance-connect:SendSSHPublicKey",
      "Resource": "arn:aws:ec2:ap-south-1:123456789012:instance/i-xxxxxxxx"
    },
    {
      "Sid": "DescribeInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceConnectEndpoints"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 2 — Add GitHub Secrets

Go to **GitHub → Repo → Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | e.g. `ap-south-1` |
| `EC2_INSTANCE_ID` | e.g. `i-xxxxxxxx` |

> No SSH key secret needed — ephemeral keys are generated automatically by AWS CLI.

### Step 3 — GitHub Actions Workflow

**.github/workflows/deploy.yml:**

```yaml
name: Deploy to EC2

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Install AWS CLI v2
        run: |
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip -q awscliv2.zip
          sudo ./aws/install --update
          aws --version

      - name: Deploy via EICE
        run: |
          aws ec2-instance-connect ssh \
            --instance-id ${{ secrets.EC2_INSTANCE_ID }} \
            --connection-type eice \
            --os-user ubuntu \
            --region ${{ secrets.AWS_REGION }} \
            -- "
              cd /app &&
              git pull origin main &&
              npm install &&
              pm2 restart app
            "
```

> AWS CLI generates a temporary SSH key pair on the fly, pushes the public key to the instance for 60 seconds, connects, runs the commands, and discards the key. No key management required.

---

## Security Group Summary

| Security Group | Inbound | Outbound |
|---|---|---|
| `eice-sg` | None | All traffic (default) |
| `ec2-sg` | SSH port 22 from `eice-sg` only | All traffic (default) |

---

## IAM Permissions Summary

| Permission | Purpose |
|---|---|
| `ec2-instance-connect:OpenTunnel` | open the EICE tunnel |
| `ec2-instance-connect:SendSSHPublicKey` | push ephemeral key to instance (auto, no key file needed) |
| `ec2:DescribeInstances` | look up instance details |
| `ec2:DescribeInstanceConnectEndpoints` | find the endpoint |

---

## Billing

| Item | Cost |
|---|---|
| EICE endpoint | Free |
| Data transfer out via EICE | $0.01 per GB |
| Cross-AZ transfer (if applicable) | $0.01 per GB extra |

> Normal SSH terminal usage is effectively free. Cost only applies for large file transfers.

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Endpoint stuck in `create-in-progress` | wait 2-3 mins and refresh |
| Connection hangs | check EC2 SG has inbound SSH from `eice-sg` |
| `AccessDeniedException` | add `ec2-instance-connect:OpenTunnel` to IAM policy |
| `bad permissions` on key (Windows) | use WSL or fix with `icacls` |
| Wrong OS user | Amazon Linux = `ec2-user`, Ubuntu = `ubuntu` |
| `Invalid choice` error for ssh command | upgrade to AWS CLI v2 |
