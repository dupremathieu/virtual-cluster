# Cirun / EC2 KVM evaluation — 2026-10-18

KVM is required for SEAPATH CI. Software emulation is too slow for this workload.

## Cirun integration

The Cirun GitHub App is active on `dupremathieu/virtual-cluster`, and its AWS
connection is verified. Its dedicated IAM user can manage EC2 resources in
`eu-west-3`; it has no IAM or S3 permissions. Credentials are not stored in Git.

The first runner used:

- `m7i.2xlarge`: 8 vCPUs and 32 GiB RAM;
- Canonical Ubuntu 24.04 amd64, AMI `ami-001b955040bc46321`;
- a 150 GiB gp3 root volume, deleted on termination;
- On-Demand capacity and a 10-minute diagnostic job timeout.

Workflow: <https://github.com/dupremathieu/virtual-cluster/actions/runs/39142947485>

Cirun successfully created the instance and registered its GitHub Actions runner.
The job then failed in four seconds because the CPU did not expose Intel VMX.
Cirun subsequently terminated the instance.

The following request in `.cirun.yml` was **not forwarded**:

```yaml
extra_config:
  CpuOptions:
    NestedVirtualization: enabled
```

Evidence:

- the instance's `CpuOptions` contained core/thread counts but no
  `NestedVirtualization` setting;
- the CloudTrail `RunInstances` event had no `cpuOptions` request parameter;
- `/proc/cpuinfo` in the runner lacked `vmx`.

The YAML field is a requested setting, not a working configuration on Cirun.
Changing the AMI cannot replace this EC2 launch-time option. Do not run the full
cluster workflow on this runner until the KVM diagnostic passes.

## Native EC2 verification

An isolated test uses the same instance type and AMI with the explicit AWS CLI
option `--cpu-options NestedVirtualization=enabled`. Runtime verification passed:

```text
KVM nested parameter: Y
SEAPATH_QMP_KVM_VERIFIED {'enabled': True, 'present': True}
SEAPATH_KVM_PROBE_PASS
SEAPATH_KVM_PROBE_EXIT=0
```

QEMU started with `-accel kvm -cpu host,vmx=on,enforce`; libvirt's KVM domain
capabilities and creation/deletion of an Open vSwitch bridge also passed. This
confirms these host dependencies are usable on this EC2 instance type.

The direct probe started without an SSH key or inbound rules. A temporary EC2
Instance Connect key and an SSH rule restricted to the operator's source IP were
used to retrieve the final journal after the console output proved insufficient.
Temporary instances, their root volumes and the diagnostic security group are
removed after verification.

This test is separate from Cirun. Passing it does not establish that a guest
deployed inside a SEAPATH node can also use hardware KVM; that needs a subsequent
test at the additional virtualization level.

Automatic diagnostic runs are disabled until Cirun supports the launch option;
the workflow remains available as a manual diagnostic once published on the
repository's default branch.

## Required Cirun change

Cirun needs to forward `CpuOptions.NestedVirtualization=enabled` in its AWS
`RunInstances` request, or expose an equivalent supported option. Public AWS extra
configuration documentation currently describes disk mappings but not CPU options.

Suggested support request (not sent):

> We are evaluating Cirun for SEAPATH CI on AWS. KVM is mandatory. Our
> `m7i.2xlarge` runner in `eu-west-3` starts successfully, but `extra_config:
> {CpuOptions: {NestedVirtualization: enabled}}` is ignored: CloudTrail shows no
> `cpuOptions` in RunInstances and the runner has no VMX. Can Cirun forward this
> EC2 option or provide a supported way to enable nested virtualization at launch?

References:

- <https://docs.cirun.io/reference/yaml>
- <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html>
- <https://github-aws-runners.github.io/terraform-aws-github-runner/modules/runners/>
