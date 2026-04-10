Since this was a technical deep dive into S3 permissions and GitHub automation, here is a structured **README.md** that captures the final architecture, the "gotchas" we solved, and the final configuration.

---

# S3 Static Site PoC: Secure Deployment & IP Restriction

This document outlines the architecture and findings for a secure, automated static site hosting setup on AWS S3, utilizing GitHub Actions for CI/CD and IP-based access control.

## 🏗️ Architecture Overview
* **Hosting:** AWS S3 (Static Website Hosting enabled).
* **Security Model:** "Bucket Owner Enforced" (ACLs Disabled) with a dual-statement Bucket Policy.
* **Access Control:** Restricted to a specific **IPv4/CIDR** range.
* **CI/CD:** GitHub Actions using AWS CLI `s3 sync` with IAM User bypass.

## 🛠️ Configuration & Implementation

### 1. S3 Bucket Policy
The core of the security lies in the "Ticket & Bouncer" logic. We provide a broad `Allow` to enable the static website features, immediately followed by a high-priority `Deny` for anyone outside the trusted IP or the Deployment ARN.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPublicRead",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::timetable-bucket/*"
        },
        {
            "Sid": "IPAndPipelineRestrict",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::timetable-bucket",
                "arn:aws:s3:::timetable-bucket/*"
            ],
            "Condition": {
                "NotIpAddress": {
                    "aws:SourceIp": "YOUR_IP/32"
                },
                "ArnNotLike": {
                    "aws:PrincipalArn": [
                        "arn:aws:iam::ACCOUNT_ID:user/github-s3-sync-user",
                        "arn:aws:iam::ACCOUNT_ID:root"
                    ]
                }
            }
        }
    ]
}
```

### 2. GitHub Actions Workflow
The deployment excludes metadata and documentation files to keep the bucket clean.

```yaml
- name: Deploy to S3
  run: |
    aws s3 sync . s3://${{ secrets.AWS_S3_BUCKET }} \
    --delete \
    --exclude ".git/*" \
    --exclude ".github/*" \
    --exclude "*.md"
```

## 🔍 Key Findings & Troubleshooting

### 1. The "Default Deny" Trap
**Finding:** A bucket policy containing *only* a `Deny` statement for "Not-IP" will still block the "Allowed" IP.
**Reason:** AWS requires an explicit `Allow` to grant access. If the `Deny` statement ignores you, but no `Allow` statement exists, AWS defaults to a "Default Deny."
**Solution:** Always pair a `Deny` restriction with a broad `Allow` statement.

### 2. ACL Reset Issue
**Finding:** Manually setting "Public Read" on objects via the AWS Console is a temporary fix that breaks upon the next sync.
**Reason:** The `s3 sync` command replaces objects. Under the **Bucket Owner Enforced** setting, new objects inherit the bucket's default private state.
**Solution:** Disable ACLs entirely and manage all permissions via the Bucket Policy for a "Single Source of Truth."

### 3. Website vs. REST Endpoints
**Finding:** Visiting the standard S3 URL results in a 403 error for the root directory.
**Reason:** The standard API endpoint (`s3.amazonaws.com`) does not support "Index Documents." 
**Solution:** Use the **Website Endpoint** (`s3-website-region.amazonaws.com`) which correctly maps `/` to `index.html`.

### 4. IAM ARN Precision
**Finding:** Policy evaluation fails if the ARN is not precise.
**Reason:** AWS policies require the 12-digit **Account ID**, not the account name. 
**Solution:** Use `arn:aws:iam::123456789012:user/username` for the pipeline exception.

---

## 🚀 Future Recommendations
* **HTTPS:** S3 Website Endpoints do not support SSL (HTTPS) natively for custom domains. Transition to **CloudFront** if encrypted traffic is required.
* **IPv6:** If access is lost, verify if the ISP has switched to an IPv6 address and update the `NotIpAddress` range accordingly.
