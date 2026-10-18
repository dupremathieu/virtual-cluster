# Terraform EC2 runner evaluation

This deployment replaces Cirun for the next KVM diagnostic. It uses
[`terraform-aws-github-runner` v7.11.0](https://github.com/github-aws-runners/terraform-aws-github-runner/releases/tag/v7.11.0)
with an EC2 launch template that explicitly enables nested virtualization.
The previous native EC2 probe passed on this instance type; this Terraform
integration still needs its first deployment and GitHub Actions run.

## Initial limits

- Region: Paris (`eu-west-3`), existing default VPC and default subnets.
- Repository: `dupremathieu/virtual-cluster` only.
- One ephemeral `m7i.2xlarge` at a time: 8 vCPUs, 32 GiB RAM, On-Demand.
- Canonical Ubuntu 24.04, encrypted 150 GiB gp3 root disk, deleted on termination.
- KVM, libvirt, Open vSwitch and Docker installed at boot.
- No idle pool. Each runner handles one job, then terminates. An independent
  systemd timer shuts the instance down after two hours; OS shutdown terminates it.
- No inbound security-group rule or SSH key. CloudWatch runner agent and SSM
  session access are disabled for this first test; Lambda logs are retained seven days.
- No Lambda reserved concurrency: the account currently has only five concurrent
  executions, which cannot support AWS's minimum unreserved allowance when creating
  a reservation. Concurrent Lambda invocations can still be throttled.

This is not a cost-free deployment. EC2 runtime, EBS, public IPv4 and transfers
can be billed. The webhook, Lambda, SQS, S3, SSM and logging resources also remain
until `terraform destroy`, even when there are no EC2 runners. Credit eligibility
and final charges must be checked in the account's billing console.

## Create and install an owned GitHub App

Open the URL in [github-app-setup-url.txt](github-app-setup-url.txt). It prefills
a private App with these repository permissions:

- Actions: read;
- Checks: read;
- Administration: write;
- Metadata: read (mandatory).

Keep the App's webhook inactive: the setup helper creates a separate repository
webhook after deployment. Create the App, note its **App ID**, generate a private
key, and install the App on **only** `dupremathieu/virtual-cluster`.
Do not use the App's Client ID or Cirun's App credentials.

Store the downloaded PEM outside Git, for example under this directory's ignored
`.local/` folder, and restrict it to your user (`chmod 600`). Do not paste it in
a chat, a Terraform variable or a shell command argument.

## Bootstrap and deploy

Run these commands from `infra/github-runner`. Terraform, AWS CLI, Python 3,
OpenSSL and authenticated GitHub CLI are required. The configured AWS profile
must be able to create the module's IAM roles, Lambda functions, EC2 launch
template, S3 bucket, SQS queues, API endpoint and SSM parameters.

```bash
aws --profile seapath --region eu-west-3 sts get-caller-identity
python3 download-lambdas.py
terraform init
terraform fmt -check
terraform validate

# Replace the example App ID and local key path.
python3 configure-github-app.py --app-id 123456 --private-key .local/github-app.pem

terraform plan -out=runner.tfplan
terraform apply runner.tfplan

python3 configure-github-app.py --app-id 123456 --private-key .local/github-app.pem \
  --webhook-url "$(terraform output -raw webhook_endpoint)"
```

The helper authenticates to GitHub as the App and checks its permissions and
repository installation before writing anything to AWS. It stores the App ID,
base64 PEM and webhook secret as SSM SecureStrings under
`/seapath/ec2-runner/github-app`. Terraform receives their names and ARNs only;
the secret values are not loaded into its state. The helper reuses the existing
webhook secret when run again and creates or updates only a repository webhook
whose URL matches this deployment.

The Lambda ZIPs are downloaded from the pinned upstream release and verified
against SHA-256 digests recorded in `download-lambdas.py`. They are not committed.
The local state, plans, artifacts and `.local/` are ignored. Keep local state
safe: it is needed to remove the deployment.

## First diagnostic

The prepared workflow is
[`ec2-terraform-diagnostic.yml`](../../.github/workflows/ec2-terraform-diagnostic.yml),
with labels `[self-hosted, linux, x64, seapath-ec2-kvm]` and a ten-minute job timeout.
It verifies CPU VMX, `/dev/kvm`, QEMU hardware acceleration with VMX exposed to
the guest CPU, libvirt and Open vSwitch. It does not boot the SEAPATH cluster or
verify a further nested guest inside SEAPATH.

The workflow is manual-only. GitHub requires a `workflow_dispatch` workflow to
exist on the default branch before it can be dispatched. Once the backend and
App are ready, either publish it there or add a narrowly scoped temporary push
trigger on the evaluation branch to test it without changing the default branch.
Do not dispatch before the webhook is configured: queued events are not replayed
automatically by this setup.

Confirm the job passes and the EC2 instance terminates before moving the full
Ansible/SEAPATH workflow onto these labels.

## Remove the evaluation

Disable the repository webhook and stop any active diagnostic before destroying
the infrastructure. Verify the EC2 runner has terminated first: dynamically
created runners are not Terraform-managed resources.

```bash
terraform destroy
```

The externally managed GitHub App, repository webhook and three App credential
SSM parameters are not removed by Terraform. Remove them explicitly when retiring
this integration, and revoke the App's private key if no longer used.

## Local validation — 2026-10-18

`terraform fmt -check`, `terraform validate` and an authenticated plan succeeded:
74 resources to create, zero to change or destroy. The planned launch template
contains `cpu_options.nested_virtualization = "enabled"` and shutdown behavior
`terminate`. The rendered Ubuntu startup template, including upstream runner
scripts with a placeholder S3 distribution URL, passes `bash -n`. The App
helper's JWT signature was independently verified with OpenSSL using a temporary
test key. No infrastructure has been applied yet.

References: [upstream setup](https://github-aws-runners.github.io/terraform-aws-github-runner/getting-started/),
[external SSM credentials](https://github-aws-runners.github.io/terraform-aws-github-runner/configuration/),
[runner module](https://github-aws-runners.github.io/terraform-aws-github-runner/modules/runners/).
