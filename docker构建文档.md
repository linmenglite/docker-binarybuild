### 构建环境
| 硬件信息 | SG2042 |
| --- | --- |
| 架构 | RISC-V64 |
| 操作系统 | openEuler 24.03 (LTS) |
| GCC 版本 | 7.3.0 |
| G++ 版本 | 7.3.0 |
| go 版本| 1.22.5 |
| btrfs-progs版本 | 6.6.3 |
| pkg-config版本 | 1.9.5 | 
| Docker 版本 | 27.1.1 |
### 构建过程
#### 依赖安装
##### 安装go
安装go 1.22.5，先确定编译平台，然后下载对应的go版本，检查是否安装成功，并设置环境变量
```shell
#确定go安装版本
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

#检查是否安装成功
go version

#配置环境变量
export GOPROXY=https://proxy.golang.org
export GOTOOLCHAIN=local
export GOPATH=${BASE_DIR}/gopath
export GOROOT=${BASE_DIR}/go${GO_VERSION}

```
##### 安装 containerd rootlesskit runc tini
先从gitee上拉取moby源码，然后分别安装containerd rootlesskit runc tini
```shell
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

my_array=("containerd" "rootlesskit" "runc" "tini") 
for item in "${my_array[@]}"  
do  
    ./hack/dockerfile/install/install.sh "$item"  
done

```
#### 编译docker
##### 安装 docker 守护进程
编译完成 dockerd 和 docker-proxy 文件后，将其放置在/usr/local/bin目录中
```shell
cd ${MOBY_REPO_PATH}

VERSION=${DOCKER_VERSION} DOCKER_GITCOMMIT=1 ./hack/make.sh binary
cp ${MOBY_REPO_PATH}/bundles/binary-daemon/* /usr/local/bin
```
##### 安装 dockercli 
先从gitee上拉取cli源码，然后进行编译，最后将二进制文件放在/usr/local/bin 目录下
```shell
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
git checkout tags/v${DOCKERCLI_VERSION}
make 

cp ${DOCKER_CLI_REPO_PATH}/build/* /usr/local/bin
```
#### 配置文件
##### 配置 docker.service 文件
```shell
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

#赋予执行权限
chmod a+x /etc/systemd/system/docker.service
```

##### 配置 daemon.json 文件
```shell
cat > /etc/docker/daemon.json << EOF
{
    "data-root": "/home/docker_data",
    "log-driver": "json-file",
    "log-opts": {"max-size": "500m", "max-file": "3"}
}
EOF
```