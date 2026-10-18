# Full SEAPATH test on EC2 — cost evaluation, 2026-10-18

This evaluation measures a cold CI run on one ephemeral EC2 runner. The three
SEAPATH hypervisors and their guest VM run inside that one instance; they are
not four additional EC2 instances. Estimated costs below use public On-Demand
prices before credits, discounts and taxes. They are not an AWS invoice.

## Configuration and scope

- Paris (`eu-west-3`), Linux `m7i.2xlarge`: 8 vCPUs and 32 GiB RAM.
- Ubuntu 24.04, nested virtualization explicitly enabled at EC2 launch.
- One encrypted 150 GiB gp3 root volume: 3,000 IOPS and 125 MiB/s, both baseline.
- One public IPv4 address, default VPC, no NAT gateway or idle runner pool.
- Three SEAPATH nodes, each with 4 virtual CPUs and 8 GiB RAM. Guest CPU time is
  shared on the EC2 instance; assigning those virtual CPUs creates no extra EC2 bill.
- Node CPU nesting set to `vmx`, matching the Intel host.
- SEAPATH Ansible pinned to `5361df70aefcb43d822bbe3d2917538b80492f04`.
- No persistent image or dependency cache: bootstrap, download, setup, tests,
  report generation, cleanup and shutdown contribute to runner lifetime.
- Workflow timeout: 90 minutes; independent instance expiry: two hours.

Workflow: [ansible-setup-ec2.yml](../.github/workflows/ansible-setup-ec2.yml).
It provisions the nodes, probes hardware KVM inside all three, grows root filesystems,
configures the cluster, deploys a guest VM, runs Cukinia, tests migration and generates
the existing PDF report. The inherited list of virtual-environment Cukinia
exclusions remains explicit in the workflow; a successful job does not assert
physical hardware or real-time certification.

Image SHA-256 values recorded during download:

```text
0831ce616b060148f57b25150bd7aa3c0905c560544fa5b4a3e2c9ce26d696df  seapath-host-efi-image-seapath-hypervisor.rootfs.wic.qcow2
5444197603844140d34b41603a49e69d70f3e022ab4d995100cbe055e0aec4be  seapath-v2.0.0-guest-efi-image.rootfs.wic.qcow2
```

## Prices retrieved on 2026-10-18

| Component | Public price | Effective hourly amount for this runner |
| --- | ---: | ---: |
| EC2 Linux On-Demand, shared tenancy | USD 0.4704/hour | USD 0.470400/hour |
| gp3 capacity, Paris | USD 0.0928/GB-month | USD 0.018710/hour for 150 GiB in October |
| Public IPv4 | USD 0.005/address-hour | USD 0.005000/hour |
| **Direct runner estimate** | | **USD 0.494110/hour** |

EC2 and EBS prices were retrieved with AWS Price List `GetProducts` in `us-east-1`,
filtered to `regionCode=eu-west-3`. The EC2 query additionally filters
`instanceType=m7i.2xlarge`, `operatingSystem=Linux`, `tenancy=Shared`,
`preInstalledSw=NA`, `capacitystatus=Used`. The EC2 SKU is `D26FR8DKJBSZ8AX6`;
the gp3 capacity SKU is `XCKADFE99D2BK5V6` (`volumeApiName=gp3`).

For October's 31 days, the EBS hourly equivalent is
`150 × 0.0928 / (31 × 24)`. EBS capacity is billed for the provisioned 150 GiB,
even if only a small part is occupied. EC2, gp3 and public IPv4 billing use
one-second increments with a 60-second minimum. EBS and address lifetimes can
differ slightly from instance lifetime; using one common measured duration is
an estimate, with a few seconds of possible difference during creation/deletion.

The direct estimate excludes Lambda, SQS, API Gateway, S3, SSM, CloudWatch,
outbound transfers, GitHub artifact storage and taxes. The Terraform control
plane remains deployed between runs and incurs its own usage; it does not keep
an EC2 instance running. Credits affect the amount payable, not the public price
used to compare CI alternatives.

Sources:

- [AWS Price List GetProducts API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_pricing_GetProducts.html)
- [EC2 On-Demand pricing and billing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [EBS pricing and second-based prorating](https://aws.amazon.com/ebs/pricing/)
- [Public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)

## Execution measurements

The [full workflow](https://github.com/dupremathieu/virtual-cluster/actions/runs/39146638020)
completed successfully at revision `811057c`. The GitHub job took
**13 min 10 s**. Actual instance lifetime, including bootstrap
and automatic shutdown, was **14 min 30 s**.

- EC2 instance: `i-08ac12939efafb32a`.
- Launch: `2026-10-18T16:47:57+00:00`.
- Automatic termination initiated: `2026-10-18T17:02:27+00:00`.
- Instance state subsequently confirmed `terminated`; zero EBS volumes and zero
  GitHub runners remained. Nested VMs were destroyed by the workflow first.

| Measured interval | Duration |
| --- | ---: |
| GitHub job, including tooling and teardown | 13 min 10 s |
| EC2 launch to GitHub job start | 1 min 08 s |
| Job completion to automatic termination request | 0 min 12 s |
| **Full instance lifetime used for cost** | **14 min 30 s** |

Selected step timings are below. They are parts of the job duration above,
not additional billable intervals.

| Step | Duration |
| --- | ---: |
| Fetch base image from S3 | 1 min 13 s |
| Clone and prepare SEAPATH Ansible repo | 0 min 21 s |
| Terraform init + apply (provision VMs) | 0 min 08 s |
| Verify KVM inside all three SEAPATH nodes | 0 min 03 s |
| ansible-setup | 5 min 45 s |
| Deploy a VM in the SEAPATH cluster | 0 min 45 s |
| Prepare report generation | 1 min 23 s |
| Run Cukinia tests on all hypervisor nodes | 1 min 20 s |
| Test VM migration | 0 min 17 s |
| Generate test report | 0 min 06 s |
| Destroy nested cluster | 0 min 05 s |

| Direct cost component | Estimated amount |
| --- | ---: |
| EC2 (870 seconds) | USD 0.113680 |
| 150 GiB gp3, prorated over October | USD 0.004522 |
| Public IPv4 | USD 0.001208 |
| **Estimated direct cost of the successful full run** | **USD 0.119410 ≈ USD 0.12** |

For illustration, 100 identical cold runs would represent approximately
**USD 11.94** in direct runner costs. This is a projection of one observed run,
not a statistical average, and still excludes the services listed above.

The [preparatory attempt](https://github.com/dupremathieu/virtual-cluster/actions/runs/39146282573)
stopped before VM creation because `make` was absent from the minimal Ubuntu AMI.
The workflow now installs it explicitly. That instance lived four minutes,
estimated at **USD 0.032941** in direct costs.
Both attempts in this evaluation therefore total about
**USD 0.152350 ≈ USD 0.15**,
excluding controller services and the earlier standalone KVM diagnostics.

## Test results and limits

QEMU reported `{'enabled': True, 'present': True}` from inside each of
`node1`, `node2` and `node3`, verifying hardware acceleration at the additional
virtualization level. Cluster setup, guest deployment and the existing migration
playbook completed; the PDF report was generated.

| Cukinia result file | Test cases | Failures covered by existing exclusions |
| --- | ---: | ---: |
| cukinia_cluster_node1.xml | 289 | 1 |
| cukinia_node1.xml | 359 | 4 |
| cukinia_node2.xml | 359 | 4 |
| cukinia_node3.xml | 359 | 4 |
| **Total** | **1366** | **13** |

The 13 failures belong to four IDs already excluded by the source workflow:
`SEAPATH-00109` (fs.aio-max-nr), `SEAPATH-00084` (syslog),
`SEAPATH-00031` and `SEAPATH-00032` (IOMMU). There were no failing IDs outside
that inherited exclusion list. A green workflow therefore does not mean zero
raw Cukinia failures.

Immediately after setup, Ceph reported `HEALTH_WARN` for clock skew on two
monitors, while all three monitors had quorum, all three OSDs were up/in and
placement groups were active+clean. The simultaneous Pacemaker snapshot still
showed no elected DC and three offline nodes. Guest deployment and migration
subsequently succeeded, and the later Cukinia cluster checks for running
Corosync/Pacemaker, available Ceph monitors and non-error Ceph health passed.
The recorded snapshots do **not** prove final `HEALTH_OK` or permanent clock
synchronization. Clock stability and a final synchronized health snapshot should
be checked before treating this as a production-quality cluster benchmark.

Artifacts:

- [PDF test report](https://github.com/dupremathieu/virtual-cluster/actions/runs/39146638020/artifacts/12143704017).
- [Raw XML, facts and timing metadata](https://github.com/dupremathieu/virtual-cluster/actions/runs/39146638020/artifacts/12143634203), retained seven days.

The temporary push trigger has been removed; the workflow is manual-only again.
As with the diagnostic workflow, GitHub dispatch requires its publication on the
default branch, or a deliberately enabled temporary trigger on the evaluation branch.
