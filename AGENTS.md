# AGENTS.md

## Repo Shape
- This repo provisions a 3-node SEAPATH virtual cluster with Terraform/libvirt and drives setup through the external `seapath/ansible` repo.
- The Makefile default for the Ansible checkout is `./ansible`, not a sibling directory; override with `ANSIBLE_REPO=/path/to/ansible`.
- Local runtime files are intentionally gitignored: `terraform/terraform.tfvars`, Terraform state/cache, `./ansible/`, qcow2/wic/raw images, and `keys/fence_virt.key`.
- Any commit in this repo must be signed off with `git commit -s`.

## Provisioning Flow
- Create `terraform/terraform.tfvars` from `terraform.tfvars.example`; `base_image_path` is required and must point to a SEAPATH qcow2 with an `ansible` user and pre-authorized SSH key.
- Use `make init` before the first Terraform run, then `make apply`; `make apply` first creates host OVS bridges through `sudo ovs-vsctl`/`ovs-ofctl`.
- Host prerequisites that are easy to miss: running `libvirtd`, running `openvswitch`, a `default` libvirt storage pool, and passwordless sudo for `/usr/bin/ovs-vsctl` and `/usr/bin/ovs-ofctl`.
- `make destroy` deletes snapshots first, runs `terraform destroy`, then removes the host OVS bridges; do not expect Terraform alone to own the OVS bridge lifecycle.
- `LIBVIRT_URI` controls Makefile `virsh`; Terraform has a separate `libvirt_uri` variable, both default to `qemu:///system`.
- CI-built `.wic.gz` artifacts must be converted before use: `make convert-image WIC=<path> [OUT=<dir>] [SIZE=<size>] [FORCE=1]` (script: `scripts/wic2qcow2.sh`, default out dir `images/`, output `<name>.wic.qcow2`). A sibling `.bmap` is ignored. Use `SIZE=` (e.g. `40G`) so the rootfs has room for `ansible-grow-rootfs`.

## Ansible Setup
- Prepare the external Ansible repo with `./prepare.sh` before `make ansible-*`.
- Useful targets: `make ansible-ping`, `make ansible-setup-network`, `make ansible-setup-ceph`, `make ansible-setup-ha`, `make ansible-setup`, and `make ansible-grow-rootfs`.
- Pass focused Ansible flags with `ANSIBLE_OPTS`, for example `make ansible-setup ANSIBLE_OPTS='-v --check'`.
- The Ceph target runs `playbooks/cluster_setup_cephadm.yaml` in the external Ansible repo; older docs or habits may mention `cluster_setup_ceph.yaml`.

## Networking Gotchas
- The admin network is NAT `192.168.100.0/24`; nodes are `192.168.100.101`-`103` via Terraform DHCP host reservations.
- The cluster network is a 3-segment OVS-backed ring, not Linux bridges; Linux bridges drop STP BPDUs and break guest OVS RSTP/Ceph quorum.
- Current inventory interface names are `enp1s0` for admin and `enp2s0`/`enp3s0` for `team0_0`/`team0_1`. Some Terraform/XSLT comments still mention `enp0s3`-`enp0s5`; trust `inventory/seapath-sandbox.yaml` when editing Ansible wiring.
- Ring IPs are static in inventory: node1 `192.168.55.1`, node2 `192.168.55.2`, node3 `192.168.55.3`.

## Fencing
- Host STONITH uses `fence_virtd` listening on TCP port `1229`; run `sudo ./scripts/fence-setup-host.sh` for host setup on Fedora/Ubuntu/Debian.
- VM key setup is `make fence-setup`, then rerun `make ansible-setup-ha`; after `terraform destroy && make apply`, push the key again.
- The shared key is `keys/fence_virt.key` locally and `/etc/cluster/fence_virt.key` in VMs; it is gitignored.

## Validation
- Terraform-only check: `cd terraform && terraform fmt -check && terraform validate`.
- Inventory linting must be run from the external Ansible repo, for example `ansible-lint -c ansible-lint.conf ../seapath-virtual-sandbox/inventory/seapath-sandbox.yaml`.
