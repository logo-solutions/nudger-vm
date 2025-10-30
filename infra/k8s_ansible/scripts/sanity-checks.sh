#!/bin/bash
set -e
echo "=== SANITY CHECKS Kubernetes Master ==="
for phase in prep containerd k8s_packages init_master flannel kube_proxy kubeconfig_user; do
  echo -e "\n#### [$phase] ####"
  case $phase in
    prep)
      lsmod | grep br_netfilter; sysctl net.bridge.bridge-nf-call-iptables; swapon --show;;
    containerd)
      systemctl status containerd --no-pager | grep Active; crictl info | grep '"name"';;
    k8s_packages)
      which kubeadm kubelet kubectl; kubelet --version;;
    init_master)
      kubectl get nodes; kubectl get pods -n kube-system;;
    flannel)
      kubectl -n kube-flannel get pods; kubectl -n kube-flannel get ds;;
    kube_proxy)
      kubectl -n kube-system get ds kube-proxy;;
    kubeconfig_user)
      sudo -u ansible kubectl get nodes;;
  esac
done
"
