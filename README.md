# 构建工具

Containerfile

## 基础镜像

（1）选择SUSE的镜像更容易构建：

[Elemental - Immutable Linux for Rancher](https://elemental.docs.rancher.com/custom-images/)

但是要忍受sl-micro后台服务带来的不便，而且有的时候仅仅屏蔽这些服务又会带来新的问题。


（2）选择openSUSE的镜像更容易自定义：

[Portal:Container/Base Container - openSUSE Wiki](https://en.opensuse.org/Portal:Container/Base_Container)

[How to Build Elemental OS Images](https://oneuptime.com/blog/post/2026-03-20-elemental-build-os-images/view)


# 构建产物

(1) OCI镜像

(2) 分片LiveCD


# 推送方式

本地的各个Layer Blob，分别直接推送到GHCR和ACR。

# 备注

~~lightdm的自启动有问题，需要在tty中手动启动；sddm的自启动没问题。~~
