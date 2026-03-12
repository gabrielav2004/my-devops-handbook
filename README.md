# DevOps Learning Documentation

> **Purpose**: Personal learning repository documenting deployment pipelines, observability stacks, and real-world implementation experiences.  
> **Author**: DevOps Engineer  
> **Last Updated**: December 2025

---

## 📚 Documentation Index

This repository contains comprehensive documentation of DevOps practices, architectural decisions, and lessons learned from hands-on implementation.

### **1. CI/CD Pipeline Architecture**
📄 [`cicd-pipeline-architecture-evolution.md`](./cicd-pipeline-architecture-evolution.md)

**What it covers:**
- Evolution from webhook-based to VPN + SSH deployment
- Flask webhook server implementation
- OpenVPN + SSH direct deployment
- AWS Dynamic Security Group approach
- Complete code examples and security comparisons

**Key Topics:**
- GitHub Actions workflows
- Webhook security (HMAC signatures)
- VPN tunnel configuration
- Deployment automation
- Multi-workflow routing

**When to read:** Building automated deployment pipelines or evaluating deployment strategies

---

### **2. Log Observability Stack**
📄 [`log-observability-stack-evolution.md`](./log-observability-stack-evolution.md)

**What it covers:**
- Journey from Grafana Alloy to OpenTelemetry Collector + Parseable
- Configuration challenges with Alloy + Loki
- Migration to simpler SQL-based observability
- Complete setup guides for all stacks

**Key Topics:**
- Log aggregation patterns
- OpenTelemetry Collector configuration
- Parseable vs Loki comparison
- SQL vs LogQL trade-offs
- Resource optimization

**When to read:** Setting up log aggregation or choosing observability tools

---

### **3. Coolify Deployment Guide**
📄 [`Coolify_docs.md`](./Coolify_docs.md)

**What it covers:**
- Deploying AI Stamp Rally Application using Coolify
- Self-hosted PaaS deployment process
- Configuration and troubleshooting
- Coolify platform learning experience

**Key Topics:**
- Coolify platform setup
- Application deployment workflows
- Platform features and limitations
- Real-world deployment patterns

**When to read:** Exploring Coolify as a deployment platform or deploying similar applications

---

## 🎯 Quick Navigation by Topic

### **Deployment & CI/CD**
- [CI/CD Pipeline Evolution](./cicd-pipeline-architecture-evolution.md) - Webhook vs VPN vs Dynamic SG
- [Coolify Deployment](./Coolify_docs.md) - PaaS-based deployment

### **Observability & Logging**
- [Log Observability Stack](./log-observability-stack-evolution.md) - Alloy → Loki → Parseable journey

### **Security**
- [Webhook Security](./cicd-pipeline-architecture-evolution.md#flask-webhook-server-implementation) - HMAC signature verification
- [VPN Setup](./cicd-pipeline-architecture-evolution.md#openvpn-server-setup) - OpenVPN configuration
- [AWS Security Groups](./cicd-pipeline-architecture-evolution.md#iteration-3-dynamic-security-group-considered) - Dynamic IP whitelisting

### **Tools & Technologies**
- **GitHub Actions**: CI/CD Pipeline doc
- **OpenVPN**: CI/CD Pipeline doc
- **Flask**: CI/CD Pipeline doc  
- **OpenTelemetry**: Observability doc
- **Parseable**: Observability doc
- **Loki & Grafana**: Observability doc
- **Coolify**: Coolify doc

---

## 📊 Architecture Evolution Summary

### **CI/CD Pipeline Journey**
```
Webhook + Flask Server (4.8/10)
         ↓
    VPN + SSH (8.9/10) ✅ RECOMMENDED
         ↓
  Dynamic SG (6.7/10) - Considered but rejected
```

### **Observability Stack Journey**
```
Alloy + Loki + Grafana (5/10)
         ↓
 OTel + Loki + Grafana (7/10)
         ↓
   OTel + Parseable (8/10) ✅ RECOMMENDED
```

---

## 🎓 Key Learnings Across All Docs

### **1. Simplicity Over Complexity**
- VPN + SSH beat custom webhooks for small teams
- SQL queries beat LogQL for familiarity
- Fewer components = less operational overhead

### **2. Appropriate Technology for Scale**
- Don't build for Netflix scale when you have 5 deployments/day
- Match architecture to actual needs, not anticipated future scale
- Boring, proven technology often wins

### **3. Configuration Matters**
- YAML > HCL for most teams (familiarity)
- Clear error messages save hours of debugging
- Industry standards (OTel) provide better support

### **4. Security Through Defense in Depth**
- Multiple independent security layers (VPN + SSH keys)
- Temporary public exposure is still risky
- OIDC credentials > long-lived access keys

### **5. The Best Code is No Code**
- Eliminating Flask server removed 500+ lines to maintain
- Built-in tools (GitHub Actions logs) vs custom observability
- Throw away work when simpler solutions exist

---

## 🛠️ Tech Stack Reference

### **Deployment**
| Tool | Used In | Status | Rating |
|------|---------|--------|--------|
| GitHub Actions | CI/CD Pipeline | ✅ Active | 9/10 |
| OpenVPN | CI/CD Pipeline | ✅ Active | 9/10 |
| Flask | CI/CD Pipeline | ❌ Deprecated | 5/10 |
| Coolify | Coolify Doc | ✅ Active | TBD |
| Docker | All Docs | ✅ Active | 10/10 |

### **Observability**
| Tool | Used In | Status | Rating |
|------|---------|--------|--------|
| OpenTelemetry Collector | Observability | ✅ Active | 9/10 |
| Parseable | Observability | ✅ Active | 8/10 |
| Grafana Alloy | Observability | ❌ Deprecated | 5/10 |
| Loki + Grafana | Observability | ❌ Deprecated | 7/10 |

### **Infrastructure**
| Tool | Used In | Purpose |
|------|---------|---------|
| AWS EC2 | Multiple | Deployment servers |
| Docker Compose | Multiple | Container orchestration |
| SSH | CI/CD Pipeline | Secure remote access |

---

## 📖 How to Use This Repository

### **For Learning**
1. Read documents in chronological order of your journey
2. Compare "before" and "after" architectures
3. Review code examples and adapt to your needs
4. Note the "Key Learnings" sections in each doc

### **For Reference**
1. Use the Quick Navigation above to find specific topics
2. Search for tool names (OpenVPN, Parseable, etc.)
3. Copy code snippets and configuration examples
4. Reference rating comparisons for tool selection

### **For Team Onboarding**
1. Start with recommended solutions (VPN + SSH, OTel + Parseable)
2. Show evolution to explain "why" behind decisions
3. Use as discussion material for architecture reviews
4. Reference when evaluating new tools

---

## 🔄 Document Status

| Document | Last Updated | Status | Completeness |
|----------|--------------|--------|--------------|
| CI/CD Pipeline | Dec 2025 | ✅ Final | 100% |
| Observability | Dec 2025 | ✅ Final | 100% |
| Coolify | TBD | 📝 Active | TBD |

---

## 🚀 Quick Start Guides

### **Deploy with VPN + SSH**
See: [CI/CD Pipeline - Iteration 2](./cicd-pipeline-architecture-evolution.md#iteration-2-vpn--ssh-direct-deployment)

**Setup time:** 2-3 hours  
**Complexity:** Low  
**Best for:** Small teams (1-10 people)

### **Set Up Log Observability**
See: [Observability - OTel + Parseable](./log-observability-stack-evolution.md#iteration-3-opentelemetry-collector--parseable-final)

**Setup time:** 30 minutes  
**Complexity:** Low  
**Best for:** Basic log aggregation needs

### **Deploy with Coolify**
See: [Coolify Documentation](./Coolify_docs.md)

**Setup time:** TBD  
**Complexity:** TBD  
**Best for:** TBD

---

## 💡 Related Resources

### **External Documentation**
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Parseable Docs](https://www.parseable.io/docs)
- [OpenVPN Community](https://openvpn.net/community-resources/)
- [Coolify Docs](https://coolify.io/docs)

### **Useful Tools**
- [Base64 Encoder](https://www.base64encode.org/) - For auth headers
- [YAML Validator](https://www.yamllint.com/) - Validate configs
- [Docker Hub](https://hub.docker.com/) - Container images

---

## 📝 Contributing to This Repo

This is a personal learning repository, but feedback and suggestions are welcome:

1. **Found an error?** Note it for future updates
2. **Have a suggestion?** Document alternative approaches
3. **Tried something similar?** Compare outcomes and learnings

---

## 🏆 Success Metrics

**What "success" looks like from these implementations:**

✅ **Deployment time:** 5 minutes (down from 20+ minutes with webhooks)  
✅ **Failure debugging:** 2 minutes (check GitHub Actions logs)  
✅ **Onboarding time:** 1 hour (down from 1 day)  
✅ **Infrastructure maintenance:** <1 hour/week  
✅ **Log query time:** 30 seconds (SQL vs learning LogQL)  

---

## 📬 Questions or Feedback

For questions about implementations or discussions about architectural decisions, feel free to open an issue or discussion in this repository.

---

## 📄 License

These documents are shared for educational purposes. Code examples are provided as-is for learning and adaptation to your own use cases.

---

**Last Updated:** December 2025  
**Repository Purpose:** Learning and reference documentation for DevOps practices  
**Maintenance:** Actively updated based on new learnings and implementations
