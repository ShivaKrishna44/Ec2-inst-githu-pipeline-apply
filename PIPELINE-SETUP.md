# Pipeline setup (init, plan, apply)

Account 589389425618, region us-east-1. Repo: `ShivaKrishna44/Ec2-inst-githu-pipeline-apply`.

Flow: PR runs fmt, validate, init, plan and posts the plan as a comment. Merge to main runs plan again, then waits for approval in environment `dev`, then applies that same plan. Destroy is never in the pipeline.

## Step 0. Finish the state migration first

The state key is the same as the old `Terraform\ec2` folder. Check it is in S3:

```bash
aws s3 ls s3://shivakrishna-tf-state-dev/terraform-practice/ec2/
```

You should see `terraform.tfstate`. If not, in the old `Terraform/ec2` folder run:

```bash
terraform state list
cp terraform.tfstate ec2-before-migration.tfstate
terraform init -migrate-state    # answer: yes
terraform plan
```

Expected: SG and default VPC no change, instance 1 to add.

## Step 1. Bucket check

```bash
aws s3api head-bucket --bucket shivakrishna-tf-state-dev
aws s3api get-bucket-versioning --bucket shivakrishna-tf-state-dev
```

## Step 2. OIDC provider (once per account)

```bash
aws iam list-open-id-connect-providers
```

If `token.actions.githubusercontent.com` is not listed:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

## Step 3. Role with trust policy

Save as `trust.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::589389425618:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:ShivaKrishna44/Ec2-inst-githu-pipeline-apply:pull_request",
          "repo:ShivaKrishna44/Ec2-inst-githu-pipeline-apply:ref:refs/heads/main",
          "repo:ShivaKrishna44/Ec2-inst-githu-pipeline-apply:environment:dev"
        ]
      }
    }
  }]
}
```

```bash
aws iam create-role --role-name github-terraform-ec2 --assume-role-policy-document file://trust.json
```

## Step 4. Least-privilege policy

Save as `policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::shivakrishna-tf-state-dev" },
    { "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::shivakrishna-tf-state-dev/terraform-practice/ec2/*" },
    { "Effect": "Allow", "Resource": "*", "Action": [
      "ec2:DescribeImages", "ec2:RunInstances", "ec2:TerminateInstances",
      "ec2:DescribeInstances", "ec2:DescribeInstanceAttribute", "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceCreditSpecifications", "ec2:ModifyInstanceAttribute",
      "ec2:DescribeVolumes", "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags", "ec2:CreateTags", "ec2:DeleteTags",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:ModifyVpcAttribute",
      "ec2:DescribeSubnets", "ec2:DescribeRouteTables", "ec2:DescribeNetworkAcls",
      "ec2:CreateDefaultVpc" ] }
  ]
}
```

```bash
aws iam put-role-policy --role-name github-terraform-ec2 --policy-name tf-ec2 --policy-document file://policy.json
aws iam get-role --role-name github-terraform-ec2 --query Role.Arn --output text
```

Copy the ARN. If apply says access denied for an action, add that action.

## Step 5. GitHub settings

Repo, Settings:

1. Secrets and variables, Actions, new secret `AWS_ROLE_ARN` = the role ARN.
2. Environments, new `dev`. Add yourself as required reviewer. Deployment branches: main only.
3. Branches, protect `main`: require a pull request.

## Step 6. First run

```bash
cd /c/Devops/Repository/Ec2-inst-githu-pipeline-apply
terraform fmt
terraform init
git checkout -b add-pipeline
git add .
git commit -m "add terraform pipeline"
git push -u origin add-pipeline
```

Commit `.terraform.lock.hcl` (it is not ignored). Open a PR, read the plan comment, merge, then approve the `dev` environment in the Actions run.

## Step 7. Destroy (by hand only)

```bash
terraform plan -destroy
terraform destroy
```

`aws_default_vpc` destroy only removes it from state.

## Step 8. Troubleshooting

| Error | Fix |
|---|---|
| AssumeRoleWithWebIdentity failed | Check trust policy sub values (case matters), secret name, and `id-token: write`. Find the real `sub` in CloudTrail. |
| Error acquiring state lock | Wait, or `terraform force-unlock <ID>` after confirming no run is active. |
| Backend initialization required | Run `terraform init`. |
| NoSuchBucket | Bucket name or region wrong in `backend.tf`. |
| Saved plan is stale | Re-run the workflow so plan runs again. |
| Nothing runs | Changed files must match the `paths` filter. |
| fmt fails | Run `terraform fmt` locally and commit. |
| InvalidGroup.Duplicate for `allow_tls` | State was not migrated. Do Step 0. |
| Your query returned no results (AMI) | `aws ec2 describe-images --owners 973714476881 --filters "Name=name,Values=Redhat-9-DevOps-Practice*"` |

## Warning

SSH (22) is open to 0.0.0.0/0 on an instance from a course AMI. Restrict to your IP when you can.
