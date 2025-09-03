# EQoS 方案3：基于MAC地址的全面IPv6限速

## 概述

方案3是EQoS的增强版IPv6限速解决方案，专门解决单个设备拥有多个IPv6地址导致限速失效的问题。通过MAC地址识别设备，对该设备的所有IPv6地址进行统一限速控制。

## 问题背景

现代设备（如手机、平板）通常会获得多个IPv6地址：
- **链路本地地址**：fe80::xxx（用于本地网络通信）
- **全局单播地址1**：2409:8a70:xxx（主要公网地址）
- **全局单播地址2**：2409:8a70:xxx（临时隐私地址）
- **其他临时地址**：IPv6隐私扩展产生的地址

传统的单IP限速方法只能限制其中一个地址，其他地址仍可全速访问，导致限速失效。**方案3通过MAC地址识别，能够匹配设备的所有IPv6地址类型，确保无一遗漏。**

## 方案3解决方案

### 三层防护机制

#### 方法3A：ebtables MAC层控制
```bash
# 在数据链路层直接基于MAC地址标记数据包
ebtables -A FORWARD -s aa:bb:cc:dd:ee:ff -j mark --set-mark 0x1001
ebtables -A FORWARD -d aa:bb:cc:dd:ee:ff -j mark --set-mark 0x1001
```

#### 方法3B：ip6tables全类型地址规则
```bash
# 为该MAC地址的所有IPv6地址类型创建限速规则

# 全局单播地址（公网地址）
ip6tables -t mangle -A EQOS_OUT -d 2409:8a70:8a1:cc0:417d:xxx/128 -j MARK --set-mark 0x1001
ip6tables -t mangle -A EQOS_OUT -d 2409:8a70:8a1:cc0:e868:xxx/128 -j MARK --set-mark 0x1001

# 链路本地地址（内网通信）
ip6tables -t mangle -A EQOS_OUT -d fe80::xxx/128 -j MARK --set-mark 0x1001

# 对应的入站规则
ip6tables -t mangle -A EQOS_IN -s 2409:8a70:8a1:cc0:417d:xxx/128 -j MARK --set-mark 0x1001
ip6tables -t mangle -A EQOS_IN -s 2409:8a70:8a1:cc0:e868:xxx/128 -j MARK --set-mark 0x1001
ip6tables -t mangle -A EQOS_IN -s fe80::xxx/128 -j MARK --set-mark 0x1001
```

#### 方法3C：MAC通配符匹配
```bash
# 使用MAC地址通配符匹配未来的IPv6地址
ip6tables -t mangle -A EQOS_OUT -m mac --mac-source aa:bb:cc:dd:ee:ff -j MARK --set-mark 0x1001
```

### IPv6地址全类型匹配机制

#### 地址发现和分类
方案3通过以下方式确保所有IPv6地址都被正确识别和限制：

```bash
# 获取设备的全局单播地址（公网地址）
global_ipv6s=$(ip -6 neigh show | grep "$mac" | awk '{print $1}' | grep -v "^fe80")
# 示例结果：2409:8a70:8a1:cc0:417d:xxx 2409:8a70:8a1:cc0:e868:xxx

# 获取设备的链路本地地址（内网通信）
local_ipv6s=$(ip -6 neigh show | grep "$mac" | awk '{print $1}' | grep "^fe80")
# 示例结果：fe80::xxx
```

#### 全覆盖保障
1. **基于MAC地址识别**：无论设备有多少个IPv6地址，都通过唯一的MAC地址进行关联
2. **分类处理**：分别处理全局地址和链路本地地址，确保无遗漏
3. **动态适应**：当设备获得新的IPv6地址时，自动添加到限制规则中
4. **三层防护**：即使某个地址规则失效，MAC层和通配符规则仍然生效

#### 地址类型说明
- **fe80::xxx**：链路本地地址，用于同一网段内的设备通信，**必须限制**
- **2409:8a70:xxx**：全局单播地址，用于互联网访问，**必须限制**
- **临时地址**：IPv6隐私扩展产生的地址，**自动检测并限制**

### 动态更新机制

- **定时更新**：每5分钟自动检查并更新IPv6地址规则
- **手动更新**：`/usr/sbin/eqos update_ipv6`
- **状态持久化**：MAC-MARK映射保存在 `/tmp/eqos_mac_marks.txt`
- **全类型更新**：更新时重新扫描所有IPv6地址类型

## 使用方法

### 1. 基本限速设置

```bash
# 启动EQoS（总带宽：下行30Mbps，上行20Mbps）
/usr/sbin/eqos start 30 20

# 为MAC地址设置IPv6限速（下行10Mbps，上行2Mbps）
/usr/sbin/eqos add_ipv6 aa:bb:cc:dd:ee:ff 10 2
```

### 2. 查看设备MAC地址

```bash
# 查看连接设备的MAC地址
arp -a
ip neigh show

# 查看IPv6邻居表
ip -6 neigh show
```

### 3. 动态更新IPv6规则

```bash
# 手动更新所有已注册MAC的IPv6规则
/usr/sbin/eqos update_ipv6

# 查看当前规则状态
ip6tables -L EQOS_OUT -n -v
tc filter show dev br-lan
```

### 4. 监控和调试

```bash
# 查看实时流量
iftop -i br-lan

# 查看tc规则
tc qdisc show dev br-lan
tc class show dev br-lan
tc filter show dev br-lan

# 查看ip6tables规则
ip6tables -L -n -v

# 查看MAC-MARK映射
cat /tmp/eqos_mac_marks.txt
```

## 系统要求

### 必需组件
- `ip6tables`
- `tc` (traffic control)
- `kmod-ip6tables`
- `kmod-sched-core`
- `kmod-ifb`

### 可选组件（增强功能）
- `ebtables` + `kmod-ebtables`：启用MAC层控制
- `kmod-netfilter-xt-mac`：启用MAC通配符匹配

### 检查系统支持

```bash
# 检查ebtables支持
command -v ebtables && echo "ebtables available"

# 检查MAC模块支持
lsmod | grep ip6t_mac && echo "ip6t_mac module loaded"
modprobe ip6t_mac && echo "ip6t_mac module loadable"
```

## 工作原理

### 数据包处理流程

1. **数据包进入**：设备发送的IPv6数据包进入路由器
2. **MAC识别**：ebtables在链路层识别源MAC地址
3. **数据包标记**：为该MAC的所有流量打上相同的MARK标记
4. **流量分类**：tc根据MARK将数据包分配到对应的限速类别
5. **带宽限制**：HTB队列规则执行实际的带宽限制

### MARK值分配策略

- 使用0x1000-0x1FFF范围避免与其他应用冲突
- 每个MAC地址分配唯一的MARK值
- MARK值持久化保存，重启后保持一致

## 故障排除

### 常见问题

#### 1. 限速不生效

**检查步骤：**
```bash
# 1. 确认tc规则存在
tc qdisc show dev br-lan | grep htb

# 2. 确认ip6tables规则存在
ip6tables -L EQOS_OUT -n | grep -v "^Chain"

# 3. 确认MARK值匹配
tc filter show dev br-lan | grep handle

# 4. 检查IPv6地址是否正确
ip -6 neigh show | grep aa:bb:cc:dd:ee:ff
```

**解决方法：**
```bash
# 重新启动EQoS
/usr/sbin/eqos stop
/usr/sbin/eqos start 30 20
/usr/sbin/eqos add_ipv6 aa:bb:cc:dd:ee:ff 10 2
```

#### 2. IPv6地址变化导致限速失效

**解决方法：**
```bash
# 手动更新IPv6规则
/usr/sbin/eqos update_ipv6

# 检查定时任务是否正常
crontab -l | grep eqos
```

#### 3. 多个IPv6地址仍然超速

**检查所有IPv6地址：**
```bash
# 查看设备的所有IPv6地址
ip -6 neigh show | grep aa:bb:cc:dd:ee:ff

# 确认所有地址都有对应规则
ip6tables -L EQOS_OUT -n -v | grep "aa:bb:cc:dd:ee:ff\|2409:8a70"
```

### 性能优化

#### 1. 减少规则数量
- 优先使用MAC通配符匹配（方法3C）
- 定期清理过期的IPv6地址规则

#### 2. 调整更新频率
```bash
# 修改定时任务频率（默认5分钟）
# 编辑 /etc/crontabs/root
*/10 * * * * /usr/sbin/eqos update_ipv6  # 改为10分钟
```

## 与代理插件的兼容性

### 潜在冲突
- iptables规则优先级冲突
- MARK值冲突
- 网络接口路径变化

### 解决方案
```bash
# 1. 调整规则优先级（使用-I而不是-A）
ip6tables -t mangle -I EQOS_OUT -d xxx -j MARK --set-mark xxx

# 2. 使用独立的MARK值范围
# EQoS使用0x1000-0x1FFF，避免与代理插件冲突

# 3. 监控MARK使用情况
ip6tables -L -n -v | grep MARK
```

## 预期效果

### 成功标准
- 设备总上传速度稳定在设定值附近（如2Mbps ≈ 230-250KB/s）
- 所有IPv6地址均受限制
- 动态IPv6地址变化后限速仍然有效

### 测试方法
```bash
# 1. 速度测试
iftop -i br-lan  # 实时监控
nethogs br-lan   # 按进程监控

# 2. 多地址测试
# 在设备上同时使用多个IPv6地址进行上传测试
# 总速度应不超过设定限制
```

## 总结

方案3通过三层防护机制和动态更新功能，彻底解决了IPv6多地址限速问题：

1. **全面覆盖**：MAC层+IP层双重控制
2. **动态适应**：自动处理IPv6地址变化
3. **高兼容性**：支持各种网络环境和代理插件
4. **易于维护**：自动化更新和状态持久化

这是目前最完善的IPv6限速解决方案，适用于所有现代网络环境。