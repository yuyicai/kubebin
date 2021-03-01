#!/usr/bin/env bash

export KUBE=/tmp/.kubei/${KUBE_VERSION}
export TEMP=${KUBE}/temp
export PKG=${KUBE}/pkg

gen_kubernetes_conf() {
    echo "gen kubernetes config"
    mkdir -p ${TEMP}/kube/etc/systemd/system/
    cat <<'EOF' >${TEMP}/kube/etc/systemd/system/kubelet.service
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p ${TEMP}/kube/etc/systemd/system/kubelet.service.d/
    cat <<'EOF' >${TEMP}/kube/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generate at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF

    mkdir -p ${PKG}/kube/
    cat <<EOF >${PKG}/kube/default.sh
#!/usr/bin/env bash

KUBE_VERSION=${KUBE_VERSION}
CNI_VERSION=${CNI_VERSION}
EOF

    mkdir -p ${PKG}/kube/
    cat <<"EOF" >>${PKG}/kube/default.sh
KUBE_TGZ=$(dirname $0)/kube-${KUBE_VERSION}.tgz
echo "tar --no-same-owner -xf ${KUBE_TGZ} -C /"
tar --no-same-owner -xf ${KUBE_TGZ} -C /

CNI_TGZ=$(dirname $0)/cni-plugins-linux-amd64-${CNI_VERSION}.tgz
echo "tar --no-same-owner -xf ${CNI_TGZ} -C /opt/cni/bin"
mkdir -p /opt/cni/bin || true
tar --no-same-owner -xf ${CNI_TGZ} -C /opt/cni/bin
EOF
    chmod 755 ${PKG}/kube/default.sh
}

download_kubernetes() {
    # Download kubernetes
    echo "Download kubernetes"

    KUBE_URL=https://dl.k8s.io/${KUBE_VERSION}/kubernetes-server-linux-amd64.tar.gz

    curl -sSL -o ${TEMP}/kubernetes-server-linux-amd64.tar.gz ${KUBE_URL}
    tar xvf ${TEMP}/kubernetes-server-linux-amd64.tar.gz -C ${TEMP}

    mkdir -p ${TEMP}/kube/usr/bin
    cp -p ${TEMP}/kubernetes/server/bin/kubeadm ${TEMP}/kube/usr/bin
    cp -p ${TEMP}/kubernetes/server/bin/kubectl ${TEMP}/kube/usr/bin
    cp -p ${TEMP}/kubernetes/server/bin/kubelet ${TEMP}/kube/usr/bin

    cd ${TEMP}/kube || exit 1
    mkdir -p ${PKG}/kube
    echo "Compress ${PKG}/kube/kube-${KUBE_VERSION}.tgz"
    tar --owner=0 --group=0 -zcvf ${PKG}/kube/kube-${KUBE_VERSION}.tgz ./
}


main() {

    if [[ -d ${KUBE} ]]; then
        echo "remove ${KUBE}"
        rm -rf ${KUBE} || true
    fi

    mkdir -p ${TEMP}
    mkdir -p ${PKG}

    gen_kubernetes_conf
    download_kubernetes
}

main
