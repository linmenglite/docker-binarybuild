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
uname -m
#安装对应go版本
    #x86_64
        curl -LO https://golang.google.cn/dl/go1.22.5.linux-amd64.tar.gz
        tar -xzf go1.22.5.linux-amd64.tar.gz

    #loongarch64
        curl -LO https://golang.google.cn/dl/go1.22.5.linux-loong64.tar.gz
        tar -xzf go1.22.5.linux-loong64.tar.gz
        mv go go1.22.5

    #aarch64
        curl -LO GO_TAR=https://golang.google.cn/dl/go1.22.5.linux-arm64.tar.gz
        tar -xzf go1.22.5.linux-arm64.tar.gz
        mv go go1.22.5

    #riscv64
        curl -LO https://golang.google.cn/dl/go1.22.5.linux-riscv64.tar.gz
        tar -xzf go1.22.5.linux-riscv64.tar.gz
        mv go go1.22.5


export PATH=go安装地址/go1.22.5/bin:$PATH

#检查是否安装成功
go version

#配置环境变量
export GOPROXY=https://proxy.golang.org
export GOTOOLCHAIN=local
export GOPATH=$go安装地址/gopath
export GOROOT=$go安装地址/go1.22.5

```
##### 安装 containerd rootlesskit runc tini
先从gitee上拉取moby源码，然后分别安装containerd rootlesskit runc tini
```shell
mkdir -p $GOPATH


mkdir -p $GOPATH/src/github.com/moby
git clone https://github.com/moby/moby.git $GOPATH/src/github.com/moby


cd $GOPATH/src/github.com/moby
 
./hack/dockerfile/install/install.sh containerd  
./hack/dockerfile/install/install.sh rootlesskit
./hack/dockerfile/install/install.sh runc
./hack/dockerfile/install/install.sh tini

```
#### 编译docker
##### 安装 docker 守护进程
编译完成 dockerd 和 docker-proxy 文件后，将其放置在/usr/local/bin目录中
```shell
cd $GOPATH/src/github.com/moby
git checkout tags/v27.1.1

VERSION=27.1.1 DOCKER_GITCOMMIT=1 ./hack/make.sh binary
cp bundles/binary-daemon/* /usr/local/bin
```
##### 安装 dockercli 
先从gitee上拉取cli源码，然后进行编译，最后将二进制文件放在/usr/local/bin 目录下
```shell
    mkdir -p $GOPATH/src/github.com/docker/cli
    git clone https://github.com/docker/cli.git $GOPATH/src/github.com/docker/cli

cd $GOPATH/src/github.com/docker/cli
git checkout tags/v27.1.1
make 

cp build/* /usr/local/bin
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