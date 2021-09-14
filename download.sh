#!/usr/bin/env bash

KUBE=/tmp/.kubei/${KUBE_VERSION}
TEMP=${KUBE}/temp
PKG=${KUBE}/pkg

gen_docker_conf() {
    echo "gen docker config"
    mkdir -p ${TEMP}/container_engine/etc/systemd/system/
    cat <<EOF >${TEMP}/container_engine/etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/usr/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target

EOF

    cat <<'EOF' >${TEMP}/container_engine/etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
BindsTo=containerd.service
After=network-online.target containerd.service
Wants=network-online.target docker.socket

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID

TimeoutSec=0
RestartSec=2
Restart=always

StartLimitBurst=3
StartLimitInterval=60s

LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
}

download_docker() {
    echo "Downloading Docker"
    curl -sSL -o ${TEMP}/docker-${DOCKER_VERSION}.tgz ${DOCKER_URL}
    mkdir -p ${TEMP}/container_engine/usr/bin
    echo "Decompress docker to container_engine/usr/bin/"
    tar --strip-components=1 --no-same-owner -xvf ${TEMP}/docker-${DOCKER_VERSION}.tgz -C ${TEMP}/container_engine/usr/bin/
    rm -f ${TEMP}/docker-${DOCKER_VERSION}.tgz
    mkdir -p ${TEMP}/container_engine/etc/systemd/system

    cd ${TEMP}/container_engine || exit 1
    mkdir ${PKG}/container_engine || true
    echo "Compress ${PKG}/container_engine/docker-${DOCKER_VERSION}.tgz"
    tar --owner=0 --group=0 -zcvf ${PKG}/container_engine/docker-${DOCKER_VERSION}.tgz ./

    cat <<EOF >${PKG}/container_engine/default.sh
#!/usr/bin/env bash

DOCKER_VERSION=${DOCKER_VERSION}
EOF
    cat <<"EOF" >>${PKG}/container_engine/default.sh
DOCKER_TGZ=$(dirname $0)/docker-${DOCKER_VERSION}.tgz
echo "tar --no-same-owner -xf ${DOCKER_TGZ} -C /"
tar --no-same-owner -xf ${DOCKER_TGZ} -C /
EOF

    chmod 755 ${PKG}/container_engine/default.sh
}

download_cni() {
    # Download CNI
    echo "download cni"
    curl -sSL -o ${PKG}/kube/cni-plugins-linux-amd64-${CNI_VERSION}.tgz ${CNI_URL}
}

download_kube_image() {
    mkdir -p ${PKG}/images

    echo "Pull iamges"
    docker pull ${KUBE_APISERVER_IMAGE}
    docker pull ${KUBE_CONTROLLER_MANAGER_IMAGE}
    docker pull ${KUBE_SCHEDULER_IMAGE}
    docker pull ${KUBE_PROXY_IMAGE}
    docker pull ${PAUSE_IMAGE}
    docker pull ${ETCD_IMAGE}
    docker pull ${COREDNS_IMAGE}

    # ha images
    docker pull ${HA_NGINX_IMAGE}

    # networking
    docker pull ${NETWOEK_FALNNEL}

    docker save ${KUBE_APISERVER_IMAGE} ${KUBE_CONTROLLER_MANAGER_IMAGE} ${KUBE_SCHEDULER_IMAGE} ${ETCD_IMAGE} -o ${PKG}/images/kube_master_images.rar
    docker save ${KUBE_PROXY_IMAGE} ${PAUSE_IMAGE} ${COREDNS_IMAGE} ${HA_NGINX_IMAGE} ${NETWOEK_FALNNEL} -o ${PKG}/images/kube_node_images.rar

    cat <<"EOF" >>${PKG}/images/master.sh
docker load -i $(dirname $0)/kube_master_images.rar
EOF
    chmod 755 ${PKG}/images/master.sh

    cat <<"EOF" >>${PKG}/images/node.sh
docker load -i $(dirname $0)/kube_node_images.rar
EOF
    chmod 755 ${PKG}/images/node.sh
}

gen_pkg() {
    cd ${PKG}
    echo "Compress kube_${KUBE_VERSION}-docker_v${DOCKER_VERSION}.tgz"
    tar --owner=0 --group=0 -zcvf ../kube-files.tar.gz ./
}

fix_cin_version() {
    sed "s/^CNI_VERSION.*$/CNI_VERSION=${CNI_VERSION}/" "${PKG}"/kube/default.sh
}

main() {

    mkdir -p ${TEMP}
    mkdir -p ${PKG}

    fix_cin_version
    gen_docker_conf
    download_docker

    download_cni

    download_kube_image

    gen_pkg
}

main
