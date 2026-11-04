# collab-platform-aws

A self-hosted collaboration platform (Nextcloud, the open-source SharePoint-style option) on AWS, built entirely in Terraform and deployed only through a reviewed pull-request pipeline. Built to be created, tested, documented and destroyed.

Status: design phase.

## Architecture

```mermaid
flowchart LR
    you["You<br/>(one allowed IP)"]

    subgraph vpc["VPC 10.40.0.0/16 (2 availability zones)"]
        direction LR

        subgraph pub["Public subnets"]
            alb["Application<br/>Load Balancer<br/>HTTP :80"]
        end

        subgraph priv["Private subnets (no internet route)"]
            task["ECS Fargate task<br/>Nextcloud<br/>(image pinned by digest)"]
            ep["Interface endpoints<br/>ECR, Logs,<br/>Secrets Manager"]
            s3gw["S3 gateway<br/>endpoint"]
        end

        subgraph data["Storage"]
            efs[("EFS<br/>access points:<br/>data, config,<br/>custom_apps")]
        end

        subgraph dbs["Isolated database subnets"]
            rds[("RDS PostgreSQL 16<br/>password managed<br/>in Secrets Manager")]
        end
    end

    ecr["ECR<br/>nextcloud image"]
    sm["Secrets Manager"]
    cw["CloudWatch Logs"]

    you -->|"HTTP"| alb
    alb -->|"port 80"| task
    task -->|"NFS 2049"| efs
    task -->|"Postgres 5432"| rds
    task --> ep
    task --> s3gw
    ep -.-> ecr
    ep -.-> sm
    ep -.-> cw
    s3gw -.->|"image layers"| ecr

    classDef pubc fill:#e8f1ff,stroke:#2563eb,color:#0b2a66
    classDef privc fill:#eefaf0,stroke:#16a34a,color:#0b3d1b
    classDef dbc fill:#fff4e5,stroke:#d97706,color:#5c3300
    classDef ext fill:#f3f4f6,stroke:#6b7280,color:#111827
    class alb pubc
    class task,ep,s3gw privc
    class efs,rds dbc
    class you,ecr,sm,cw ext

    style vpc fill:#fafafa,stroke:#9ca3af,stroke-width:2px,color:#111827
    style pub fill:#f4f8ff,stroke:#93c5fd,color:#1e3a8a
    style priv fill:#f3fbf5,stroke:#86efac,color:#14532d
    style data fill:#fffaf2,stroke:#fdba74,color:#7c2d12
    style dbs fill:#fffaf2,stroke:#fdba74,color:#7c2d12
    linkStyle default stroke:#4b5563,stroke-width:1.5px
```

## Design decisions

1. Reuse, do not copy. Network and database come from the aws-platform-as-code modules, pinned to a commit.
2. Private by default. Tasks have no public IP and no internet route; they reach AWS only through VPC endpoints.
3. Secrets never in code. The database password is created and held by RDS in Secrets Manager.
4. Persistent state on EFS, because Fargate containers are disposable.
5. Lab trade-offs, stated honestly: single task, no Multi-AZ database, HTTP only unless a domain is available.

## Expected problems (what actually happened is in docs/incident-log.md)

- Fargate cannot pull the image from Docker Hub from a private subnet
- Nextcloud rejects requests from the load balancer name until trusted domains are set
- EFS mount denied until the NFS security group rule and access point permissions are right
- Pipeline role lacks EFS permissions on the first apply

## Roadmap

- [x] M1 Design doc
- [x] M2 Storage module (EFS), mirrored image, plan only
- [x] M3 Nextcloud service behind the load balancer, deployed through the pipeline
- [x] M4 Break-and-fix incidents (five real incidents, see docs/incident-log.md)
- [ ] M5 Backups, restore test, alarms (not built: lab stack has no backups, next step)
- [x] M6 Teardown through a PR, evidence (stack destroyed, cost scanner clean)

## Results

- Deployed Nextcloud 35 on ECS Fargate with RDS Postgres and EFS behind an ALB, entirely through Terraform and a plan-on-PR, apply-on-merge pipeline with no stored AWS keys (GitHub OIDC).
- Persistence test: stopped the running task on purpose. ECS started a replacement from a clean container and the admin login and an uploaded PDF were still there.
- Five real incidents found and fixed, each written up with symptom, root cause, fix and lesson in [docs/incident-log.md](docs/incident-log.md).
- Torn down through a PR (56 resources destroyed). The cost scanner from [aws-cost-guardrails](https://github.com/fiehna-hue/aws-cost-guardrails) then reported nothing billable in any region.

## Rebuild it

The teardown commit removed every resource from `envs/collab/main.tf`. To bring the stack back:

1. Mirror the pinned Nextcloud image into a new ECR repository named `nextcloud` (private subnets cannot reach Docker Hub), and check the digest in `main.tf` matches.
2. Revert the teardown commit in a PR, check the plan, and merge. The pipeline applies it.
3. Open the ALB address from the Terraform output and create the admin account in the browser.

Expect about 10 to 15 minutes, and roughly $2 to $3 a day while it runs. Tear it down again the same way.
