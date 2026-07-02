使用说明
在监控中心（主控机器）运行：
选择 1。程序会自动启动一个运行在 8000 端口的监控面板。记得在防火墙或云服务商安全组放行 8000 端口。

在需要监控的其他服务器（被控机器）运行：
选择 2。脚本会提示你输入主控端的 IP 地址。输入后，它就会每两秒在后台给主控端发送一次老老实实采集到的 CPU、内存、磁盘、网速、运行时长等数据。

管理命令：

查看主控状态：systemctl status probe-server

查看被控状态：systemctl status probe-client

卸载主控：systemctl disable --now probe-server && rm -f /etc/systemd/system/probe-server.service

卸载被控：systemctl disable --now probe-client && rm -f /etc/systemd/system/probe-client.service
