# ec2 — Terraform basics (the starting point)

The simplest possible example. Creates **one EC2 instance** protected by **one security group**.

## Files and what they do

| File | Role |
|------|------|
| `provider.tf` | Tells Terraform to use AWS in `us-east-1` and which provider version to download. Read first. |
| `ec2.tf` | Declares the security group (firewall) and the EC2 instance (VM). |

## Code flow (simple)

1. `provider.tf` → Terraform downloads the AWS plugin and points at `us-east-1`.
2. In `ec2.tf`, the instance references `aws_security_group.allow_tls.id`. That reference creates an implicit dependency.
3. Terraform builds a dependency graph and creates resources in the right order:
   - Security group first (nothing depends on before it)
   - EC2 instance second (it needs the security group id)

```
provider.tf ──► AWS (us-east-1)
                   │
ec2.tf ────────────┼──► aws_security_group.allow_tls  (created 1st)
                   └──► aws_instance.this              (created 2nd, uses the SG id)
```

## Key ideas demonstrated

- `resource` blocks — the core building block of Terraform.
- Implicit dependency — referencing another resource's attribute (`.id`) makes Terraform order things automatically.
- `ingress` / `egress` — inbound / outbound firewall rules.

## How to run

```bash
terraform init      # download the AWS provider
terraform plan      # preview what will be created
terraform apply     # create the resources
terraform destroy   # tear everything down
```

> Note: `cidr_blocks = ["0.0.0.0/0"]` opens SSH to the whole internet. Fine for a throwaway demo, not for production.
