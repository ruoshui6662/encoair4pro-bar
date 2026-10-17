# Air4 Pro 协议与适配

这是当前实现使用的已验证字段摘要，不是 OPPO 官方 SDK 或完整协议规范。公开资料来源见 [NOTICE](../NOTICE.md)。

## 通道与帧

当前匹配产品 ID `067C10`，通过 IOBluetooth 的 SDP 查询厂商服务 `0000079A-D102-11E1-9B23-00025B00A5A5` 的实际 RFCOMM 通道，不写死通道编号。

```text
AA | Length | 00 00 | Command (2B LE) | Sequence | PayloadLength (2B LE) | Payload
```

Length 为整帧字节数减 2。解析检查字段长度，支持分片和合帧，丢弃损坏前缀。查询回复只接受相应命令最近一次发出的序列号；主动通知单独按事件类型解析。

| 操作 | 命令 | 说明 |
| --- | --- | --- |
| 产品 ID | `0x0103` | 响应 `0x8103` |
| 电量查询 | `0x0106` | 响应 `0x8106`，部件索引 1 左耳、2 右耳、3 盒 |
| 模式查询 | `0x010C` | 必须携带 `01 01` |
| 设置模式 | `0x0404` | 当前使用 `01 01 mode` |
| 状态通知 | `0x0204` | 必须区分电量、佩戴及模式事件 |

## 模式确认

设置值为关闭 1、降噪 2、通透 4。回读还可能返回子档：关闭 8、降噪 16/32/64/128、通透 256，因此按模式组匹配。

成功 ACK 只会触发立即查询，新的成功回读匹配目标后才报告成功。无 ACK 时保留延迟查询兜底；回读不匹配则重试至期限，不假装切换成功。

主动通知仅将事件 `03` 视为模式；事件 `02` 是佩戴，`04` 是耳塞适配测试，不得因字节形状相似而解读为模式。

## 佩戴与切换

`0x0109` 的成功回复为 `00 count component status…`，佩戴通知为 `0x0204 02 count component status…`。左右耳状态的 bit 0 表示出盒、bit 1 表示入耳，bit 2 为开盖、bit 3 为提醒标记。`1/5` 为未入耳，`3/7` 为已入耳。未知及缺失部件不推断为未佩戴。

Air4 Pro 实机在状态 `1/1` 时对通透指令 ACK `00`，但连续模式查询仍返回关闭；状态 `3/3` 且播放声音时切换有效。切换时先立即发指令，并行读取佩戴；仅当本次新佩戴查询明确双耳未入耳、模式回读也未匹配时提前结束等待。佩戴信息缺失不会阻塞成功回读。佩戴变化还会触发模式补读，避免界面保留旧值。

## 电量与仓记录

充电位为最高位，百分比为低 7 位；通用解析区分有效 0、未知值及错误响应。当前 Air4 Pro 在无法转发盒电量时会报告盒字段 0，因此仓历史仅接受 1–100 的有效报告，未知或缺失不覆盖历史；左右耳仍保留真实 0 的语义。

记录按蓝牙地址的 SHA-256 摘要分隔设备，偏好中不保存明文地址。仓历史的存储与界面可见性分离：断开时隐藏，连接同一设备后恢复。首次使用或卸载重装后，需要实际开盖报告来建立记录。

面板内查询间隔 5 秒，后台 30 秒；开盒事件触发补读。查询有 8 秒响应期限。批量订阅无响应时尝试逐事件订阅。

## 参考

- [OPPO 产品介绍](https://www.oppo.com/en/accessories/enco-air4-pro/)
- [OppoPods 协议笔记](https://github.com/Leaf-lsgtky/OppoPods/blob/master/docs/HeyMelody_Bluetooth_Protocol_Notes.md)
- [Air4 Pro 型号表](https://github.com/Leaf-lsgtky/OppoPods/blob/master/app/src/main/assets/device_models.json)
- [QuickBuds 协议记录](https://github.com/spizganed/QuickBuds/blob/main/docs/PROTOCOL.md)
- [IOBluetooth](https://developer.apple.com/documentation/iobluetooth)
