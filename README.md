# collab-platform-aws

A self-hosted collaboration platform (Nextcloud, the open-source SharePoint-style option) on AWS, built entirely in Terraform and deployed only through a reviewed pull-request pipeline. Built to be created, tested, documented and destroyed.

Status: design phase.

## Architecture

    Internet
       |  HTTP :80 (allowed source only)
       v
    Application Load Balancer (public subnets)
       |
       v
    ECS Fargate task: Nextcloud (private subnets, no internet route)
       |-- RDS PostgreSQL        (isolated database subnets, password in Secrets Manager)
       |-- EFS file system       (mounted at /var/www/html: config, apps, user files)
       |-- ECR                   (Nextcloud image mirrored here: tasks cannot reach Docker Hub)
       '-- CloudWatch Logs and alarms

## Design decisions

1. Reuse, do not copy. Network and database come from the aws-platform-as-code modules, pinned to a commit.
2. Private by default. Tasks have no public IP and no internet route; they reach AWS only through VPC endpoints.
3. Secrets never in code. The database password is created and held by RDS in Secrets Manager.
4. Persistent state on EFS, because Fargate containers are disposable.
5. Lab trade-offs, stated honestly: single task, no Multi-AZ database, HTTP only unless a domain is available.

## Expected problems (to be documented as incidents when they happen)

- Fargate cannot pull the image from Docker Hub from a private subnet
- Nextcloud rejects requests from the load balancer name until trusted domains are set
- EFS mount denied until the NFS security group rule and access point permissions are right
- Pipeline role lacks EFS permissions on the first apply

## Roadmap

- [ ] M1 Design doc
- [ ] M2 Storage module (EFS), mirrored image, plan only
- [ ] M3 Nextcloud service behind the load balancer, deployed through the pipeline
- [ ] M4 Break-and-fix incidents
- [ ] M5 Backups, restore test, alarms
- [ ] M6 Teardown through a reverted PR, evidence
