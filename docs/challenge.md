# 🚀 Cloud Infrastructure Engineer Challenge

Welcome to the **Cloud Infrastructure Engineer Challenge!** 🎉 This challenge is designed to evaluate your ability to work with **Infrastructure as Code (IaC)**, AWS networking, IAM, and automation using modern DevOps practices.

> [!NOTE]
> You can use **any IaC tool of your choice** (Terraform preferred, but alternatives are allowed). If you choose a different tool or a combination of tools, **justify your decision!**

## ⚡ Challenge Overview

Your task is to deploy the following infrastructure on AWS:

> 🎯 **Key Objectives:**

- **An API Gateway** with a single endpoint (`GET /info`).
- **A Lambda function** triggered by the API Gateway.
- **A database instance or application backend** running in a private subnet. This can be:
  - A **PostgreSQL RDS instance** 📦
  - A **self-hosted database** on an EC2 instance 🔗
  - A **deployed application** such as WordPress hosted on EC2 🎨
- **The Lambda function must connect** to the database/backend and return basic information about its connection and status.
- **Logs from the Lambda** should be visible in CloudWatch 📊
- **Networking must include:** VPC, public/private subnets, and security groups.
- **The Lambda must be in a private subnet** and use a NAT Gateway in a public subnet for internet access 🌍

> [!IMPORTANT]
> Ensure that your solution is modular, well-documented, and follows best practices for security and maintainability.

## 📌 Requirements

### ⚙️ Tech Stack

> ⚡ **Must Include:**

- **IaC:** Any tool of your choice (**Terraform preferred**, but others are allowed if justified).
- **AWS Services:** VPC, API Gateway, Lambda, CloudWatch, NAT Gateway, RDS or EC2.

### 📦 Deliverables

> 📥 **Your submission must be a Pull Request that must include:**

- **An IaC module** that deploys the entire architecture.
- **A `README.md`** with deployment instructions and tool selection justification.
- **A working API Gateway endpoint** that responds with a JSON payload from the Lambda, including:
  - Connection status to the database or backend.
  - Basic metadata about the target system (e.g., DB version, instance type, WordPress version, etc.).
- **CloudWatch logs** from the Lambda.

> [!TIP]
> Use the `docs` folder to store any additional documentation or diagrams that help explain your solution.
> Mention any assumptions or constraints in your `README.md`.

## 🌟 Nice to Have

> 💡 **Bonus Points For:**

- **Auto Scaling & High Availability**: Implementing **Multi-AZ for RDS** or an **Auto Scaling Group for EC2** to improve availability.  
- **Load Balancer or CloudFront**: Adding an **Application Load Balancer (ALB)** or **CloudFront** for distributing traffic efficiently.  
- **Backup & Disaster Recovery**: Implementing **automated backups for RDS** or **snapshot strategies**.  
- **GitHub Actions for validation**: Running **`terraform fmt`, `terraform validate`**, or equivalent for the chosen IaC tool.  
- **Pre-commit hooks**: Ensuring linting and security checks before committing.  
- **Monitoring & Logging**: Setting up **AWS CloudWatch Alarms for infrastructure health (e.g., RDS CPU usage, EC2 status)**.  
- **Docker for local testing**: Using Docker to **simulate infrastructure components** (e.g., a local PostgreSQL instance).

> [!TIP]
> Looking for inspiration or additional ideas to earn extra points? Check out our [Awesome NaNLABS repository](https://github.com/nanlabs/awesome-nan) for reference projects and best practices! 🚀

## 📥 Submission Guidelines

> 📌 **Follow these steps to submit your solution:**

1. **Fork this repository.**
2. **Create a feature branch** for your implementation.
3. **Commit your changes** with meaningful commit messages.
4. **Open a Pull Request** following the provided template.
5. **Our team will review** and provide feedback.

## ✅ Evaluation Criteria

> 🔍 **What we'll be looking at:**

- **Correctness and completeness** of the deployed **infrastructure**.  
- **Use of best practices for networking and security** (VPC, subnets, IAM).  
- **Scalability & High Availability considerations** (optional. e.g., Multi-AZ, Auto Scaling, Load Balancer).  
- **Backup & Disaster Recovery strategies** implemented (optional).  
- **CI/CD automation using GitHub Actions and pre-commit hooks** (optional).  
- **Documentation clarity**: Clear explanation of infrastructure choices and configurations.

## 🎯 **Good luck and happy coding!** 🚀
