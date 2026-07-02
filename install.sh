cat << 'EOF' > install.sh
#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误：请以 root 权限运行此脚本 (sudo su)。"
  exit 1
fi

echo "=========================================="
echo "    欢迎使用轻量级多主机云探针一键安装脚本"
echo "=========================================="
echo "1. 安装【主控端 Server】(接收数据并展示 Web 面板)"
echo "2. 安装【被控端 Client】(采集本节点数据并上报)"
read -p "请选择安装类型 (1 或 2): " CHOICE

if [ "$CHOICE" == "1" ]; then
    echo "正在配置【主控端 Server】..."
    
    # 彻底隔离：直接将主控端源码以纯净 Base64 形式写入并解码，规避任何 Bash 字符冲突
    cat << 'SERVER_BASE64' | base64 -d > /usr/local/bin/probe_server.py
#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import os

CONFIG_FILE = "/usr/local/bin/hosts_config.json"
hosts_data = {}      
hosts_config = {}    

if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            hosts_config = json.load(f)
    except Exception:
        pass

def save_config():
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(hosts_config, f, ensure_ascii=False, indent=4)

HTML_PANEL = r"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>高级多主机集群监控面板</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: -apple-system, sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 20px; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; border-bottom: 1px solid #334155; padding-bottom: 15px; }
        h1 { margin: 0; color: #38bdf8; font-size: 24px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 25px; }
        .host-card { background: #1e293b; border-radius: 16px; padding: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.2); border: 1px solid #334155; position: relative; }
        .host-title { font-size: 18px; font-weight: bold; color: #f8fafc; margin-bottom: 5px; display: flex; justify-content: space-between; align-items: center; }
        .alias-name { cursor: pointer; border-bottom: 1px dashed #38bdf8; padding-bottom: 2px; }
        .alias-name:hover { color: #38bdf8; }
        .hostname-raw { font-size: 11px; color: #64748b; margin-left: 5px; font-weight: normal; }
        .host-meta-info { font-size: 13px; color: #94a3b8; margin-bottom: 15px; display: flex; justify-content: space-between; align-items: center; }
        .host-ip-box { display: flex; gap: 6px; align-items: center; }
        .host-uptime { font-size: 12px; color: #64748b; background: #111827; padding: 2px 8px; border-radius: 12px; }
        .flag { font-size: 16px; }
        .charts-container { display: flex; justify-content: space-around; margin-bottom: 15px; }
        .chart-box { width: 75px; text-align: center; position: relative; }
        .chart-label { font-size: 11px; color: #94a3b8; margin-top: 5px; }
        .chart-text { position: absolute; top: 22px; left: 0; right: 0; text-align: center; font-size: 12px; font-weight: bold; color: #fff; }
        .net-box { background: #111827; border-radius: 8px; padding: 10px; font-size: 13px; display: flex; justify-content: space-between; }
        .net-item { color: #38bdf8; } .net-item.out { color: #f43f5e; }
        .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #10b981; }
        .status-dot.offline { background: #ef4444; animation: blink 1s infinite; }
        @keyframes blink { 50% { opacity: 0.5; } }
    </style>
</head>
<body>
    <div class="header">
        <h1>🖥️ 节点云探针集群大屏</h1>
        <div style="font-size: 13px; color: #94a3b8;">💡 提示：点击卡片上的<b>节点名称</b>即可直接重命名。</div>
    </div>
    <div class="grid" id="hosts-grid"></div>
    <script>
        let charts = {}; let ipInfoCache = {}; 
        function maskIp(ip) { if(!ip) return "0.0.0.0"; let parts = ip.split('.'); if(parts.length === 4) return `${parts[0]}.${parts[1]}.x.x`; return ip; }
        function fetchFlag(ip, cardId) {
            if (ipInfoCache[ip]) { document.getElementById(`flag-${cardId}`).innerText = ipInfoCache[ip]; return; }
            if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) { ipInfoCache[ip] = '🏠'; document.getElementById(`flag-${cardId}`).innerText = '🏠'; return; }
            fetch(`https://ipapi.co/${ip}/json/`).then(res => res.json()).then(data => {
                if(data && data.country_code) {
                    const flag = data.country_code.toUpperCase().replace(/./g, char => String.fromCodePoint(char.charCodeAt(0) + 127397));
                    ipInfoCache[ip] = flag; document.getElementById(`flag-${cardId}`).innerText = flag;
                }
            }).catch(() => { document.getElementById(`flag-${cardId}`).innerText = '🌐'; });
        }
        function createRingChart(canvasId, value, color) {
            const ctx = document.getElementById(canvasId).getContext('2d');
            return new Chart(ctx, { type: 'doughnut', data: { datasets: [{ data: [value, 100 - value], backgroundColor: [color, '#334155'], borderWidth: 0 }] }, options: { cutout: '75%', responsive: true, maintainAspectRatio: true, plugins: { tooltip: { enabled: false } } } });
        }
        function renameHost(ip, currentName) {
            let newName = prompt(`请输入节点 [${maskIp(ip)}] 的新别名:`, currentName);
            if (newName !== null && newName.trim() !== "") {
                fetch('/api/rename', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ip: ip, name: newName.trim() }) }).then(() => updatePanel());
            }
        }
        function updatePanel() {
            fetch('/api/data').then(res => res.json()).then(resData => {
                const grid = document.getElementById('hosts-grid'); const now = Math.floor(Date.now() / 1000); const { data, config } = resData;
                for (const [ip, host] of Object.entries(data)) {
                    const cardId = `card-${ip.replace(/\./g, '-')}`; let card = document.createElement('div'); let existingCard = document.getElementById(cardId);
                    const isOffline = (now - host.time) > 6; const statusClass = isOffline ? 'status-dot offline' : 'status-dot'; const displayName = config[ip] || host.hostname;
                    if (!existingCard) {
                        card.id = cardId; card.className = 'host-card';
                        card.innerHTML = `
                            <div class="host-title"><div><span class="alias-name" id="alias-${cardId}" onclick="renameHost('${ip}', '${displayName}')">${displayName}</span><span class="hostname-raw" id="raw-${cardId}">(${host.hostname})</span></div><span class="${statusClass}" id="dot-${cardId}"></span></div>
                            <div class="host-meta-info"><div class="host-ip-box"><span class="flag" id="flag-${cardId}">⏳</span><span>IP: ${maskIp(ip)}</span></div><div class="host-uptime" id="uptime-${cardId}">⏱️ 运行: ${host.uptime || '未知'}</div></div>
                            <div class="charts-container">
                                <div class="chart-box"><canvas id="cpu-${cardId}"></canvas><div class="chart-text" id="cpu-txt-${cardId}">0%</div><div class="chart-label">CPU</div></div>
                                <div class="chart-box"><canvas id="mem-${cardId}"></canvas><div class="chart-text" id="mem-txt-${cardId}">0%</div><div class="chart-label">内存</div></div>
                                <div class="chart-box"><canvas id="disk-${cardId}"></canvas><div class="chart-text" id="disk-txt-${cardId}">0%</div><div class="chart-label">磁盘</div></div>
                            </div>
                            <div class="net-box"><div class="net-item">⬇️ 入网: <span id="net-in-${cardId}">0</span> KB/s</div><div class="net-item out">⬆️ 出网: <span id="net-out-${cardId}">0</span> KB/s</div></div>`;
                        grid.appendChild(card);
                        charts[`cpu-${cardId}`] = createRingChart(`cpu-${cardId}`, host.cpu, '#38bdf8');
                        charts[`mem-${cardId}`] = createRingChart(`mem-${cardId}`, host.memory, '#10b981');
                        charts[`disk-${cardId}`] = createRingChart(`disk-${cardId}`, host.disk, '#f59e0b');
                        fetchFlag(ip, cardId);
                    } else {
                        document.getElementById(`alias-${cardId}`).innerText = displayName;
                        document.getElementById(`alias-${cardId}`).setAttribute("onclick", `renameHost('${ip}', '${displayName}')`);
                        document.getElementById(`raw-${cardId}`).innerText = `(${host.hostname})`;
                        document.getElementById(`dot-${cardId}`).className = statusClass;
                        document.getElementById(`uptime-${cardId}`).innerText = `⏱️ 运行: ${host.uptime || '未知'}`;
                    }
                    if(!isOffline) {
                        charts[`cpu-${cardId}`].data.datasets[0].data = [host.cpu, 100 - host.cpu]; charts[`cpu-${cardId}`].update(); document.getElementById(`cpu-txt-${cardId}`).innerText = host.cpu + '%';
                        charts[`mem-${cardId}`].data.datasets[0].data = [host.memory, 100 - host.memory]; charts[`mem-${cardId}`].update(); document.getElementById(`mem-txt-${cardId}`).innerText = host.memory + '%';
                        charts[`disk-${cardId}`].data.datasets[0].data = [host.disk, 100 - host.disk]; charts[`disk-${cardId}`].update(); document.getElementById(`disk-txt-${cardId}`).innerText = host.disk + '%';
                        document.getElementById(`net-in-${cardId}`).innerText = host.net_in; document.getElementById(`net-out-${cardId}`).innerText = host.net_out;
                    }
                }
            });
        }
        setInterval(updatePanel, 2000); updatePanel();
    </script>
</body>
</html>
"""

class UpgradedMasterServer(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML_PANEL.encode('utf-8'))
        elif self.path == '/api/data':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"data": hosts_data, "config": hosts_config}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        if self.path == '/api/report':
            try:
                data = json.loads(post_data.decode('utf-8'))
                hosts_data[self.client_address[0]] = data
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"status":"ok"}')
            except Exception: self.send_response(400); self.end_headers()
        elif self.path == '/api/rename':
            try:
                req_data = json.loads(post_data.decode('utf-8'))
                target_ip, new_name = req_data.get('ip'), req_data.get('name')
                if target_ip and new_name:
                    hosts_config[target_ip] = new_name
                    save_config()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"status":"success"}')
            except Exception: self.send_response(400); self.end_headers()
    def log_message(self, format, *args): return

if __name__ == '__main__':
    HTTPServer(('0.0.0.0', 8000), UpgradedMasterServer).serve_forever()
SERVER_BASE64

    chmod +x /usr/local/bin/probe_server.py

    # 写入 Systemd 服务
    cat << 'EOF_SERVER_SERVICE' > /etc/systemd/system/probe-server.service
[Unit]
Description=Probe Master Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/env python3 /usr/local/bin/probe_server.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF_SERVER_SERVICE

    systemctl daemon-reload && systemctl enable --now probe-server.service
    echo "=========================================="
    echo "✅ 主控端（Server）安装完成并已在后台运行！"
    echo "🌐 请在浏览器访问: http://你的服务器IP:8000"
    echo "=========================================="

elif [ "$CHOICE" == "2" ]; then
    read -p "请输入主控端（Server）的 IP 地址: " SERVER_IP
    read -p "请输入主控端端口 (默认 8000): " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-8000}

    echo "正在配置【被控端 Client】..."

    cat << 'CLIENT_CODE_EOF' > /usr/local/bin/probe_client.py
#!/usr/bin/env python3
import os, time, json, urllib.request

SERVER_URL = "http://TARGET_SERVER_IP:TARGET_SERVER_PORT/api/report"

def get_uptime_str():
    try:
        with open('/proc/uptime', 'r') as f: uptime_seconds = float(f.readline().split()[0])
        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        minutes = int((uptime_seconds % 3600) // 60)
        if days > 0: return f"{days}天 {hours}小时"
        elif hours > 0: return f"{hours}小时 {minutes}分钟"
        else: return f"{minutes}分钟"
    except: return "未知"

def get_net_speed():
    def read_net():
        with open('/proc/net/dev', 'r') as f: lines = f.readlines()[2:]
        rx, tx = 0, 0
        for line in lines:
            if 'lo:' in line: continue
            parts = line.split()
            if len(parts) > 10: rx += int(parts[1]); tx += int(parts[9])
        return rx, tx
    r1, t1 = read_net()
    time.sleep(0.5)
    r2, t2 = read_net()
    return round((r2 - r1) / 1024 / 0.5, 1), round((t2 - t1) / 1024 / 0.5, 1)

def get_stats():
    with open('/proc/stat', 'r') as f: fields = [float(x) for x in f.readline().strip().split()[1:]]
    idle, total = fields[3], sum(fields)
    time.sleep(0.2)
    with open('/proc/stat', 'r') as f: fields2 = [float(x) for x in f.readline().strip().split()[1:]]
    idle_d, total_d = fields2[3] - idle, sum(fields2) - total
    cpu = round((1.0 - idle_d / total_d) * 100, 1) if total_d > 0 else 0.0

    mem = {}
    with open('/proc/meminfo', 'r') as f:
        for line in f:
            p = line.split()
            if len(p) >= 2: mem[p[0].rstrip(':')] = int(p[1])
    mem_total = mem.get('MemTotal', 0)
    mem_used = mem_total - mem.get('MemFree', 0) - mem.get('Buffers', 0) - mem.get('Cached', 0)
    mem_pct = round((mem_used / mem_total) * 100, 1) if mem_total > 0 else 0

    st = os.statvfs('/')
    disk_total = st.f_blocks * st.f_frsize
    disk_used = disk_total - (st.f_bavail * st.f_frsize)
    disk_pct = round((disk_used / disk_total) * 100, 1) if disk_total > 0 else 0

    net_in, net_out = get_net_speed()
    return {
        "hostname": os.uname()[1], "cpu": cpu, "memory": mem_pct, "disk": disk_pct,
        "net_in": net_in, "net_out": net_out, "uptime": get_uptime_str(), "time": int(time.time())
    }

if __name__ == "__main__":
    while True:
        try:
            req = urllib.request.Request(SERVER_URL, data=json.dumps(get_stats()).encode('utf-8'), headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=2) as response: response.read()
        except: pass
        time.sleep(2)
CLIENT_CODE_EOF

    sed -i "s/TARGET_SERVER_IP/${SERVER_IP}/g" /usr/local/bin/probe_client.py
    sed -i "s/TARGET_SERVER_PORT/${SERVER_PORT}/g" /usr/local/bin/probe_client.py
    chmod +x /usr/local/bin/probe_client.py

    # 写入 Systemd 服务
    cat << 'EOF_CLIENT_SERVICE' > /etc/systemd/system/probe-client.service
[Unit]
Description=Probe Agent Client
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/env python3 /usr/local/bin/probe_client.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF_CLIENT_SERVICE

    systemctl daemon-reload && systemctl enable --now probe-client.service
    echo "=========================================="
    echo "✅ 被控端（Client）安装完成并已成功上报数据！"
    echo "=========================================="

else
    echo "❌ 输入错误，脚本退出。"
    exit 1
fi
EOF
chmod +x install.sh
./install.sh
