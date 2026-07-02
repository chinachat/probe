#!/usr/bin/env python3
# client.py (带运行时长版)
import os
import time
import json
import urllib.request

# ========== 配置中心 ==========
SERVER_URL = "http://你的主控端IP:8000/api/report"  # 换成你主控端的实际IP和端口
REPORT_INTERVAL = 2  # 上报间隔（秒）
# ==============================

def get_uptime_str():
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        
        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        minutes = int((uptime_seconds % 3600) // 60)
        
        if days > 0:
            return f"{days}天 {hours}小时"
        elif hours > 0:
            return f"{hours}小时 {minutes}分钟"
        else:
            return f"{minutes}分钟"
    except Exception:
        return "未知"

def get_net_speed():
    def read_net():
        with open('/proc/net/dev', 'r') as f:
            lines = f.readlines()[2:]
        rx, tx = 0, 0
        for line in lines:
            if 'lo:' in line: continue
            parts = line.split()
            if len(parts) > 10:
                rx += int(parts[1])
                tx += int(parts[9])
        return rx, tx

    r1, t1 = read_net()
    time.sleep(0.5)
    r2, t2 = read_net()
    return round((r2 - r1) / 1024 / 0.5, 1), round((t2 - t1) / 1024 / 0.5, 1)

def get_stats():
    # CPU
    with open('/proc/stat', 'r') as f:
        fields = [float(x) for x in f.readline().strip().split()[1:]]
    idle, total = fields[3], sum(fields)
    time.sleep(0.2)
    with open('/proc/stat', 'r') as f:
        fields2 = [float(x) for x in f.readline().strip().split()[1:]]
    idle_d, total_d = fields2[3] - idle, sum(fields2) - total
    cpu = round((1.0 - idle_d / total_d) * 100, 1) if total_d > 0 else 0.0

    # 内存
    mem = {}
    with open('/proc/meminfo', 'r') as f:
        for line in f:
            p = line.split()
            if len(p) >= 2: mem[p[0].rstrip(':')] = int(p[1])
    mem_total = mem.get('MemTotal', 0)
    mem_used = mem_total - mem.get('MemFree', 0) - mem.get('Buffers', 0) - mem.get('Cached', 0)
    mem_pct = round((mem_used / mem_total) * 100, 1) if mem_total > 0 else 0

    # 磁盘
    st = os.statvfs('/')
    disk_total = st.f_blocks * st.f_frsize
    disk_used = disk_total - (st.f_bavail * st.f_frsize)
    disk_pct = round((disk_used / disk_total) * 100, 1) if disk_total > 0 else 0

    # 网速与运行时长
    net_in, net_out = get_net_speed()
    uptime = get_uptime_str()

    return {
        "hostname": os.uname()[1],
        "cpu": cpu,
        "memory": mem_pct,
        "disk": disk_pct,
        "net_in": net_in,
        "net_out": net_out,
        "uptime": uptime,
        "time": int(time.time())
    }

if __name__ == "__main__":
    print("探针客户端已启动，正在上报数据...")
    while True:
        try:
            data = get_stats()
            req = urllib.request.Request(
                SERVER_URL, 
                data=json.dumps(data).encode('utf-8'),
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req, timeout=2) as response:
                response.read()
        except Exception as e:
            print(f"上报失败: {e}")
        time.sleep(REPORT_INTERVAL)