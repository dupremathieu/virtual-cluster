# Admin network: NAT with DHCP MAC reservations for predictable IPs
resource "libvirt_network" "admin" {
  name = "seapath-sandbox-admin"

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = cidrhost(var.admin_network_cidr, 1)
      netmask = cidrnetmask(var.admin_network_cidr)
      dhcp = {
        hosts = [for i, mac in var.node_macs : {
          mac  = mac
          ip   = var.node_admin_ips[i]
          name = "node${i + 1}"
        }]
      }
    },
  ]
}

# Cluster ring segments: point-to-point L2 pipes on OVS host bridges.
#
# The bridges (ovs-ring12/23/31) are created out-of-band by the
# `ovs-setup` Makefile target because dmacvicar/libvirt does not manage
# OVS bridges; we only declare libvirt networks that attach VM taps to
# them via <virtualport type='openvswitch'/>.
#
# Why OVS on the host instead of libvirt-managed Linux bridges:
# the Linux bridge driver hardcodes BR_GROUPFWD_RESTRICTED, dropping
# STP BPDUs (01:80:C2:00:00:00). That breaks the guest-side OVS RSTP
# ring: no port ever transitions to Alternate/Discarding, the ring
# loops, and broadcast/multicast amplification stalls ceph mon quorum.
# OVS on the host forwards BPDUs transparently.

locals {
  ring_bridges = {
    ring_12 = "ovs-ring12"
    ring_23 = "ovs-ring23"
    ring_31 = "ovs-ring31"
  }
}

resource "libvirt_network" "ring_12" {
  name = "seapath-cluster-12"

  forward = {
    mode = "bridge"
  }

  bridge = {
    name = local.ring_bridges.ring_12
  }

  virtual_port = {
    params = {
      open_v_switch = {}
    }
  }
}

resource "libvirt_network" "ring_23" {
  name = "seapath-cluster-23"

  forward = {
    mode = "bridge"
  }

  bridge = {
    name = local.ring_bridges.ring_23
  }

  virtual_port = {
    params = {
      open_v_switch = {}
    }
  }
}

resource "libvirt_network" "ring_31" {
  name = "seapath-cluster-31"

  forward = {
    mode = "bridge"
  }

  bridge = {
    name = local.ring_bridges.ring_31
  }

  virtual_port = {
    params = {
      open_v_switch = {}
    }
  }
}
