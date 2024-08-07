#!/bin/bash

set -e

BASE_DIR=$(pwd)

sudo yum install pkg-config btrfs-progs gcc

GO_VERSION="1.22.5"
DOCKER_VERSION="27.1.1"
GO_BASE_URL="https://golang.google.cn/dl"
MOBY_REPO_URL="https://github.com/moby/moby.git"
MOBY_REPO_DIR="src/github.com/moby"
DOCKER_CLI_REPO_URL="https://github.com/docker/cli.git"
DOCKER_CLI_REPO_DIR="src/github.com/docker/cli"

ARCH=$(uname -m)

case "$ARCH" in
    x86_64)
        GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
        ;;
    loongarch64)
        GO_TAR="go${GO_VERSION}.linux-loong64.tar.gz"
        ;;
    aarch64)
        GO_TAR="go${GO_VERSION}.linux-arm64.tar.gz"
        ;;
    riscv64)
        GO_TAR="go${GO_VERSION}.linux-riscv64.tar.gz"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

GO_URL="${GO_BASE_URL}/${GO_TAR}"

if [ ! -d "go${GO_VERSION}" ]; then
    # 下载Go安装包
    echo "Downloading Go from ${GO_URL}..."
    curl -LO ${GO_URL}

    # 解压安装包
    echo "Extracting Go..."
    tar -xzf ${GO_TAR}

    # 移动并重命名解压后的目录
    mv go go${GO_VERSION}
else
    echo "Directory go${GO_VERSION} already exists. Skipping download."
fi

export PATH=${BASE_DIR}/go${GO_VERSION}/bin:$PATH

go version

export GOPROXY=https://proxy.golang.org
export GOTOOLCHAIN=local
export GOPATH=${BASE_DIR}/gopath
export GOROOT=${BASE_DIR}/go${GO_VERSION}

mkdir -p ${GOPATH}

MOBY_REPO_PATH="${GOPATH}/${MOBY_REPO_DIR}"

if [ ! -d "${MOBY_REPO_PATH}" ]; then
    echo "Creating directory ${MOBY_REPO_PATH}..."
    mkdir -p ${MOBY_REPO_PATH}

    # 克隆存储库
    echo "Cloning repository from ${MOBY_REPO_URL}..."
    git clone ${MOBY_REPO_URL} ${MOBY_REPO_PATH}
else
    echo "Directory ${MOBY_REPO_PATH} already exists. Skipping repository clone."
fi

cd ${MOBY_REPO_PATH}
git config --global --add safe.directory ${GOPATH}/${MOBY_REPO_PATH}
git checkout tags/v${DOCKERCLI_VERSION}


VERSION=${DOCKER_VERSION} DOCKER_GITCOMMIT=1 ./hack/make.sh binary

my_array=("containerd" "rootlesskit" "runc" "tini") 
for item in "${my_array[@]}"  
do  
    ./hack/dockerfile/install/install.sh "$item"  
done

cp ${MOBY_REPO_PATH}/bundles/binary-daemon/* /usr/local/bin

DOCKER_CLI_REPO_PATH="${GOPATH}/${DOCKER_CLI_REPO_DIR}"

if [ ! -d "${DOCKER_CLI_REPO_PATH}" ]; then
    echo "Creating directory ${DOCKER_CLI_REPO_PATH}..."
    mkdir -p ${DOCKER_CLI_REPO_PATH}

    # 克隆存储库
    echo "Cloning repository from ${DOCKER_CLI_REPO_URL}..."
    git clone ${DOCKER_CLI_REPO_URL} ${DOCKER_CLI_REPO_PATH}
else
    echo "Directory ${DOCKER_CLI_REPO_PATH} already exists. Skipping repository clone."
fi

cd ${DOCKER_CLI_REPO_PATH}
git config --global --add safe.directory ${GOPATH}/${DOCKER_CLI_REPO_PATH}
git checkout tags/v${DOCKERCLI_VERSION}
make install

cp ${DOCKER_CLI_REPO_PATH}/build/* /usr/local/bin
 
cat > /etc/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF


chmod a+x /etc/systemd/system/docker.service


mkdir -p /etc/docker

cat > /etc/docker/daemon.json << EOF
{
    "data-root": "/home/docker_data",
    "log-driver": "json-file",
    "log-opts": {"max-size": "500m", "max-file": "3"}
}
EOF

systemctl start docker
