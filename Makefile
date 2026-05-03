TERRAFORM_DIR := terraform
INVENTORY     := inventory/seapath-sandbox.yaml

# Path to a local clone of https://github.com/seapath/ansible.git
# Default: ./ansible (cqfd-friendly). Override with ANSIBLE_REPO=<path>.
ANSIBLE_REPO  ?= ./ansible
PLAYBOOKS      = $(ANSIBLE_REPO)/playbooks

# Extra ansible-playbook flags (e.g. ANSIBLE_OPTS="--check -v")
ANSIBLE_OPTS ?=

# Libvirt connection URI — allows non-root users to target the system daemon.
LIBVIRT_URI ?= qemu:///system
export LIBVIRT_DEFAULT_URI := $(LIBVIRT_URI)
VIRSH := virsh -c $(LIBVIRT_URI)

# VM domain names managed by this sandbox
NODES := seapath-node1 seapath-node2 seapath-node3

# Host OVS bridges backing the cluster ring segments
OVS_BRIDGES := ovs-ring12 ovs-ring23 ovs-ring31

# Libvirt networks used by the VMs
NETWORKS := seapath-sandbox-admin seapath-cluster-12 seapath-cluster-23 seapath-cluster-31

# Snapshot name (override with SNAPSHOT=<name>)
SNAPSHOT ?= default

.PHONY: all init plan apply destroy \
        ovs-setup ovs-teardown \
        start stop force-stop \
        snapshot restore snapshot-list snapshot-delete \
        ssh-node1 ssh-node2 ssh-node3 \
        console-node1 console-node2 console-node3 \
        ansible-ping ansible-setup \
        ansible-setup-network ansible-setup-ceph ansible-setup-ha \
        help

all: help

## Terraform lifecycle
init:
	cd $(TERRAFORM_DIR) && terraform init

plan:
	cd $(TERRAFORM_DIR) && terraform plan

apply: ovs-setup
	cd $(TERRAFORM_DIR) && terraform apply

destroy: snapshot-delete
	cd $(TERRAFORM_DIR) && terraform destroy
	$(MAKE) ovs-teardown

## Host OVS bridges for the cluster ring (require passwordless sudo to ovs-vsctl)
ovs-setup:
	@for br in $(OVS_BRIDGES); do \
		echo "Ensuring OVS bridge $$br..."; \
		sudo ovs-vsctl --may-exist add-br $$br \
			-- set bridge $$br stp_enable=false rstp_enable=false; \
		sudo ovs-ofctl add-flow $$br 'priority=100,dl_dst=01:80:c2:00:00:00,actions=FLOOD'; \
	done

ovs-teardown:
	@for br in $(OVS_BRIDGES); do \
		echo "Removing OVS bridge $$br..."; \
		sudo ovs-vsctl --if-exists del-br $$br; \
	done

## VM lifecycle
start:
	@for net in $(NETWORKS); do \
		echo "Starting network $$net..."; \
		$(VIRSH) net-start $$net 2>/dev/null || true; \
	done
	@for node in $(NODES); do echo "Starting $$node..."; $(VIRSH) start $$node; done

stop:
	@for node in $(NODES); do \
		echo "Gracefully shutting down $$node..."; \
		$(VIRSH) shutdown $$node 2>/dev/null || true; \
	done
	@echo "Waiting for VMs to power off (timeout: 120s)..."
	@timeout=120; \
	while [ $$timeout -gt 0 ]; do \
		running=0; \
		for node in $(NODES); do \
			state=$$($(VIRSH) domstate $$node 2>/dev/null | grep -i running || true); \
			if [ -n "$$state" ]; then running=1; fi; \
		done; \
		if [ $$running -eq 0 ]; then echo "All VMs stopped."; exit 0; fi; \
		sleep 2; timeout=$$((timeout - 2)); \
	done; \
	echo "WARNING: Some VMs did not shut down gracefully within 120s."; \
	echo "Run 'make force-stop' to destroy them."; \
	exit 1

force-stop:
	@for node in $(NODES); do echo "Destroying $$node..."; $(VIRSH) destroy $$node 2>/dev/null || true; done

## Snapshots
snapshot:
	@for node in $(NODES); do \
		if $(VIRSH) snapshot-info $$node $(SNAPSHOT) >/dev/null 2>&1; then \
			echo "Replacing existing snapshot $(SNAPSHOT) on $$node..."; \
			$(VIRSH) snapshot-delete $$node $(SNAPSHOT); \
		fi; \
		echo "Snapshotting $$node ($(SNAPSHOT))..."; \
		$(VIRSH) snapshot-create-as $$node $(SNAPSHOT); \
	done

restore:
	@for node in $(NODES); do echo "Restoring $$node ($(SNAPSHOT))..."; $(VIRSH) snapshot-revert $$node $(SNAPSHOT); done

snapshot-list:
	@for node in $(NODES); do echo "=== $$node ==="; $(VIRSH) snapshot-list $$node; done

snapshot-delete:
	@for node in $(NODES); do \
		for snap in $$($(VIRSH) snapshot-list $$node --name 2>/dev/null); do \
			echo "Deleting snapshot $$snap from $$node..."; \
			$(VIRSH) snapshot-delete $$node $$snap; \
		done; \
	done

## Node access
ssh-node1:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t admin@192.168.100.101 sudo -s

ssh-node2:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t admin@192.168.100.102 sudo -s

ssh-node3:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t admin@192.168.100.103 sudo -s

console-node1:
	$(VIRSH) console seapath-node1

console-node2:
	$(VIRSH) console seapath-node2

console-node3:
	$(VIRSH) console seapath-node3

## Ansible
ansible-ping:
	ansible all -i $(INVENTORY) -m ping $(ANSIBLE_OPTS)

ansible-setup:
	cd $(ANSIBLE_REPO) && ansible-playbook -i $(CURDIR)/$(INVENTORY) playbooks/seapath_setup_main.yaml $(ANSIBLE_OPTS)

ansible-setup-network:
	cd $(ANSIBLE_REPO) && ansible-playbook -i $(CURDIR)/$(INVENTORY) playbooks/seapath_setup_network.yaml $(ANSIBLE_OPTS)

ansible-setup-ceph:
	cd $(ANSIBLE_REPO) && ansible-playbook -i $(CURDIR)/$(INVENTORY) playbooks/cluster_setup_cephadm.yaml $(ANSIBLE_OPTS)

ansible-setup-ha:
	cd $(ANSIBLE_REPO) && ansible-playbook -i $(CURDIR)/$(INVENTORY) playbooks/cluster_setup_ha.yaml $(ANSIBLE_OPTS)

help:
	@echo "SEAPATH Virtual Sandbox"
	@echo ""
	@echo "Terraform:"
	@echo "  make init              Initialise Terraform (run once)"
	@echo "  make plan              Show planned changes"
	@echo "  make apply             Create/update VMs and networks (runs ovs-setup first)"
	@echo "  make destroy           Tear down all VMs and networks (runs ovs-teardown after)"
	@echo "  make ovs-setup         Create host OVS bridges for the ring"
	@echo "  make ovs-teardown      Delete host OVS bridges"
	@echo ""
	@echo "VM lifecycle:"
	@echo "  make start               Start all VMs"
	@echo "  make stop                Gracefully stop all VMs (waits up to 120s)"
	@echo "  make force-stop          Forcefully destroy all VMs immediately"
	@echo ""
	@echo "Snapshots (override name with SNAPSHOT=<name>, default: 'default'):"
	@echo "  make snapshot            Snapshot all VMs"
	@echo "  make restore             Restore all VMs to snapshot"
	@echo "  make snapshot-list       List snapshots for all VMs"
	@echo "  make snapshot-delete     Delete all snapshots for all VMs"
	@echo ""
	@echo "Node access:"
	@echo "  make ssh-node{1,2,3}      SSH into a node"
	@echo "  make console-node{1,2,3}  Open virsh serial console"
	@echo ""
	@echo "Ansible:"
	@echo "  make ansible-ping          Test connectivity to all nodes"
	@echo "  make ansible-setup         Run full SEAPATH setup"
	@echo "  make ansible-setup-network Configure network only"
	@echo "  make ansible-setup-ceph    Deploy Ceph only"
	@echo "  make ansible-setup-ha      Configure HA (Pacemaker/Corosync) only"
	@echo ""
	@echo "Pass extra flags via ANSIBLE_OPTS, e.g.:"
	@echo "  make ansible-setup ANSIBLE_OPTS='-v --check'"
