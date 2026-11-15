# Pipeline setup (one time)

The workflow is `.github/workflows/terraform-ec2.yml` at the root of the GitHub repo.
It only works if `c:\Devops\Repository\Terraform` is the root of that repo.
It only reacts to changes under `ec2/` and to the workflow file itself.

Do the steps in order. Do not skip step 0.

Replace these placeholders:

- `<ORG>` is your GitHub user or organization name (your vpc module URL shows `ShivaKrishna44`).
- `<REPO>` is the name of the GitHub repo you push `c:\Devops\Repository\Terraform` to.
- `<ENV>` is `dev` (the environment name used by the workflow).

AWS account: 589389425618. Region: us-east-1.

## Step 0. Move the old local state to S3 (do this FIRST)

Before this change, the folder had no backend. State lived in a local file, `ec2/terraform.tfstate`.
That file is not committed (git ignores it), so the pipeline cannot see it.

The pipeline starts with an EMPTY remote state.
If the old local state still lists live resources, the pipeline will try to create them again.
It will fail with a duplicate error, because a security group named `allow_tls` already exists.

When this review was written, the local state file listed two resources:
`aws_default_vpc.default` and `aws_security_group.allow_tls`. It did not list an `aws_instance`.
So there are live resources, and you must migrate. Check it yourself.

Run these in Git Bash:

```bash
cd /c/Devops/Repository/Terraform/ec2

# 1. Read-only. Lists what the local state knows about.
terraform state list
```

If it prints nothing, there are no live resources. Skip the migration and go to step 1.

If it prints resources, make a backup, then migrate:

```bash
# 2. Backup. The name ends in .tfstate, so git ignores it. Do not commit state files.
cp terraform.tfstate ec2-before-migration.tfstate

# 3. Copy the local state to S3. Answer yes when Terraform asks.
terraform init -migrate-state

# 4. Confirm the plan says what you expect.
terraform plan
```

Note: `*.tfstate.bak` is NOT in `.gitignore`, so do not name the backup that.

What you should expect in the plan: the security group and default VPC show no change.
The `aws_instance` is shown as a new resource, because the state has no instance.
It uses the AMI found by the lookup in `ec2.tf`.
If your state does list an `aws_instance` built from the old hard-coded AMI,
Terraform will replace it (destroy, then create), because the AMI changed.

If `terraform init` asks to reconfigure or migrate and you are not sure, stop and read the message.

## Step 1. Check the state bucket

These are read-only checks. Run them in Git Bash.

```bash
aws s3api head-bucket --bucket shivakrishna-tf-state-dev
aws s3api get-bucket-versioning --bucket shivakrishna-tf-state-dev
```

The second command should print `"Status": "Enabled"`.
The state key for this project is `terraform-practice/ec2/terraform.tfstate`. It must stay unique.
Your other projects use `dev/terraform.tfstate` in the same bucket, so do not reuse that key.
The pipeline does not create the bucket.

## Step 2. GitHub OIDC provider in AWS

Check if it already exists:

```bash
aws iam list-open-id-connect-providers
```

Look for an ARN ending in `oidc-provider/token.actions.githubusercontent.com`.
If it is there, skip to step 3. If it is not there, create it:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

## Step 3. Create ONE IAM role for the pipeline

Save this as `trust-policy.json` outside the repo, or do not commit it.

The `sub` values must match what GitHub puts in the token. They differ by job type:

| Job | Why | `sub` value |
|---|---|---|
| plan on a pull request | event is pull_request, job has no environment | `repo:<ORG>/<REPO>:pull_request` |
| plan on push to main or manual run | plain branch run, no environment | `repo:<ORG>/<REPO>:ref:refs/heads/main` |
| apply | job uses `environment: dev` | `repo:<ORG>/<REPO>:environment:<ENV>` |

When a job uses an environment, GitHub puts the environment in `sub` and drops the branch and the pull_request part.
That is why the apply job needs its own entry, and why the policy must list all three.
Source: the [GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::589389425618:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": [
            "repo:<ORG>/<REPO>:pull_request",
            "repo:<ORG>/<REPO>:ref:refs/heads/main",
            "repo:<ORG>/<REPO>:environment:<ENV>"
          ]
        }
      }
    }
  ]
}
```

Note: GitHub documents a newer `sub` format for repos created after July 15, 2026.
It includes numeric IDs, like `repo:<ORG>@<OWNER-ID>/<REPO>@<REPO-ID>:pull_request`.
If your repo is new, use that format in the policy instead.
Repos made before that date keep the old format unless you opt in.
Source: the same GitHub OIDC reference above.

Create the role:

```bash
aws iam create-role \
  --role-name github-terraform-ec2 \
  --assume-role-policy-document file://trust-policy.json
```

Copy the role ARN from the output. You need it in step 5.

## Step 4. Give the role the permissions it needs

Do not use AdministratorAccess. Give only these.
Save this as `permissions-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateBucketList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::shivakrishna-tf-state-dev"
    },
    {
      "Sid": "StateObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::shivakrishna-tf-state-dev/terraform-practice/ec2/*"
    },
    {
      "Sid": "Ec2ForThisConfig",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceCreditSpecifications",
        "ec2:ModifyInstanceAttribute",
        "ec2:DescribeVolumes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeTags",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcAttribute",
        "ec2:ModifyVpcAttribute",
        "ec2:DescribeSubnets",
        "ec2:DescribeRouteTables",
        "ec2:DescribeNetworkAcls",
        "ec2:CreateDefaultVpc"
      ],
      "Resource": "*"
    }
  ]
}
```

Why these EC2 actions: the AMI lookup reads images. The instance needs create, read, tag and terminate.
The security group needs create, delete and rule changes. The default VPC resource reads the VPC and its parts.
`CreateDefaultVpc` is only used if the account has no default VPC.
Most EC2 read actions do not support limits by resource, so `Resource` is `*`.

If a run fails with `UnauthorizedOperation`, the message names the missing action. Add it and run again.

Attach it to the role:

```bash
aws iam put-role-policy \
  --role-name github-terraform-ec2 \
  --policy-name terraform-ec2 \
  --policy-document file://permissions-policy.json
```

The `.tflock` lock file sits next to the state file in S3.
That is why the role needs `PutObject` and `DeleteObject` on the `terraform-practice/ec2/` prefix.

Note: a pull request plan uses the same role as apply. A bad pull request could change the workflow and apply.
That is why the `dev` environment needs a required reviewer and the branch rule in step 5.
A stronger pattern is two roles (read-only for plan, write for apply). It is not needed for practice.

## Step 5. GitHub settings

1. Repo, Settings, Secrets and variables, Actions, New repository secret. Name: `AWS_ROLE_ARN`. Value: the role ARN from step 3.
2. Repo, Settings, Environments, New environment. Name: `dev`.
3. In `dev`, tick Required reviewers and add yourself. (On private repos this needs a paid plan.)
4. In `dev`, under Deployment branches and tags, choose Selected branches and add `main`.
5. Repo, Settings, Branches, Add branch protection rule for `main`. Tick Require a pull request before merging and Require status checks to pass. Pick the `Plan` check once it has run once.

The role ARN is not a password, but keep it as a secret so it stays out of logs.

Before your first pull request, format the files and commit the result.
The pipeline fails on `terraform fmt -check`, and the files were formatted by hand.
Also commit `ec2/.terraform.lock.hcl`. The pipeline needs it for the same provider hashes as your laptop.

```bash
cd /c/Devops/Repository/Terraform/ec2
terraform fmt
terraform init
git status
```

## Step 6. First run, safely

1. Create a branch and make a small change under `ec2/`. Push it and open a pull request into `main`.
2. Wait for the `Plan` job. A comment with the plan appears on the pull request.
3. Read the plan. Check the counts and the resources. Look for any line that says `destroy` or `replace`.
4. Merge the pull request.
5. The push to `main` starts the workflow. `Plan` runs again, then `Apply` waits.
6. Open the run, click Review deployments, tick `dev`, click Approve and deploy.
7. Watch the `Apply` job. It applies the saved plan file from the same run.

You can also run it by hand: Actions, terraform-ec2, Run workflow, pick `main` and `plan` or `apply`.

## Step 7. Destroy (by hand only)

The pipeline has no destroy on purpose. From Git Bash:

```bash
cd /c/Devops/Repository/Terraform/ec2
terraform init
terraform plan -destroy
terraform destroy
```

Read the destroy plan before you type yes.
It will terminate the instance and delete the security group.
For `aws_default_vpc`, the provider docs say destroy only removes it from state and does not delete the VPC, unless `force_destroy` is true. It is not set here.

Cost: a t3.micro in us-east-1 is roughly a quarter of a dollar per day. This is an estimate. Check the AWS pricing page.
The instance boots a course AMI, so also check that AMI for extra charges.
Destroy the instance when you finish learning.

## Step 8. Troubleshooting

| Error | Likely cause | What to do |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The `sub` or `aud` in the trust policy does not match the token. Often the apply job (environment) or the pull request job is missing from the list. | Check the three `sub` values in step 3. Check the secret `AWS_ROLE_ARN`. Check the OIDC provider exists. Check the `<ORG>/<REPO>` spelling and case. |
| `Error acquiring the state lock` | Another run or a crashed run holds the lock file in S3. | Wait. Check no other run is active. If a run crashed, run `terraform force-unlock <LOCK_ID>` by hand, using the ID from the error. |
| `Backend initialization required` | The backend config changed, or `init` did not run in this folder. | Run `terraform init -reconfigure` locally. In CI, check the working directory is `ec2`. |
| `NoSuchBucket` | The bucket in `backend.tf` does not exist in this account. | Run the step 1 check. |
| The apply does not match what was approved | The plan was for an older commit or the state changed after the plan. | Terraform rejects a stale plan file. Run the workflow again and approve the new plan. |
| Pull request from a fork has no plan | Forks get no secrets and no OIDC token. | This is intended. Ask the author to push a branch in the main repo. |
| Nothing runs on a push | The change is outside the `paths` filter. | Edit a file under `ec2/` or the workflow file. |
| `terraform fmt` fails | A file is not formatted. | Run `terraform fmt -recursive` in `ec2` and commit. |
| Duplicate security group `allow_tls` (`InvalidGroup.Duplicate`) | You skipped step 0. The remote state is empty, but the security group already exists. | Do step 0 to move the old state to S3. Or import the group. Do not delete it by hand if the state is the only record. |
| `Your query returned no results` for the AMI lookup | The AMI is not visible to this account in us-east-1, or its name changed. | Run `aws ec2 describe-images --owners 973714476881 --filters "Name=name,Values=Redhat-9-DevOps-Practice*" --region us-east-1 --query "Images[].Name"`. If it prints nothing, the AMI is not shared with this account. |

To see the real `sub` of a run, read the CloudTrail event `AssumeRoleWithWebIdentity`. Do not print the token itself.
