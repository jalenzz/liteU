# LiteU

登录 U 净后，按定位选择附近洗衣房，查看洗衣机、烘干机、洗鞋机空闲与等待时间；显示当前账号使用中的机器剩余时间，结束前 1 分钟本地通知提醒。主屏幕小组件展示洗衣机最近一次快照。

不含预约、扫码、单台机号。直连 `https://phoenix.ujing.online`，无自建后端。

## 架构

```mermaid
flowchart LR
  subgraph app [iOS App]
    Auth[登录]
    Near[附近店]
    Status[空闲状态]
    Snap[快照]
  end
  subgraph sys [系统]
    Loc[Core Location]
    W[WidgetKit]
  end
  Auth --> API[phoenix.ujing.online]
  Loc --> Near
  Near --> API
  Status --> API
  Status --> Snap
  Snap --> W
```

| 数据 | 存放 |
|---|---|
| JWT | Keychain |
| 选中的 `storeId` | App Group UserDefaults |
| 状态快照（空闲、总数、最短等待、更新时间） | App Group，供小组件读取 |

网络：`URLSession`。

## 用户流程

1. 无 JWT → 手机号 → 发短信 → 验证码 → 存 token。
2. 已登录、未选店 → 定位（可手动改点）→ `stores/near` → 多选保存。
3. 首页按选中 `storeId` 拉各类机器状态，同时拉当前账号使用中的订单，下拉刷新。
4. 每次成功查询写快照；小组件展示快照。系统刷新约 15 分钟。
5. 每次拉到使用中订单后重排结束提醒；已不在列表里的订单撤销提醒。
6. 查询 401 → 清 token → 回登录。

## API

基址：`https://phoenix.ujing.online`。业务成功：`code == 0`。

登录与查询使用不同客户端头。发短信签名密钥：`Secrets/captcha-hmac-key.txt`。

### 发短信

`GET /api/v1/wechat/captcha/create`

| | |
|---|---|
| Query | `mobile`，`type=1`，`nonce`（UUID hex），`timestamp`（unix 秒） |
| 签名 | `signature = Base64(HMAC-SHA256(key, nonce \|\| timestamp))`，`key` 为密钥文件的 UTF-8 字节 |
| Header | `x-app-code: BO`，`x-app-version: 1.1.0` |

手机号：`1` + 10 位数字。

### 登录

`POST /api/v1/login`

JSON：`{"mobile","captcha"}`。Header 同发短信。Token：`data.token`。

### 附近洗衣房

`GET /api/v1/stores/near`

Query：`lat`，`lont`，`scope`（默认 2000），`page=1`，`size=50`，`mode=BA`。

Header：`Authorization: Bearer <jwt>`，`x-app-code: ZA`，`x-app-version: 2.4.18`。

列表：`data.storeList[]`。洗衣机计数来自 `storeInfo` 中 `category == 1`：`num` 为总数，`access` 为空闲。

### 机型与等待时间

`GET /api/v1/devices/reserve?storeId=`

Header 同附近店。该店出现在附近结果里时调用。

`data.devices[].device`：`deviceTypeName`，`free`，`total`，`waitTime`（分钟）。按名称归类：含「鞋」为洗鞋机，含「烘干」或「干衣」为烘干机，其余为洗衣机。同店结果缓存 60 秒。

### 使用中订单

`GET /api/v1/orders/running`

Header 同附近店。`data` 为订单数组，或包着订单数组的对象；`data` 为空视为无订单。每项取 `orderId`（无则 `id`）。

`GET /api/v1/orders/{orderId}/detail`

Header 同附近店。取 `statusRemark`，`remainTime`（秒），`deviceTypeName`，`storeName`。结束时刻 = 拉取时刻 + `remainTime`；`remainTime` 为 0（如启动中）时不倒计时、不提醒。

## 领域模型

```text
StoreStatus
  id, name
  idle, total
  machines: [MachineType]
  kinds: [KindStatus]
  waitMinutes

MachineType
  name, kind, idle, total, waitMinutes

KindStatus
  kind (washer / dryer / shoe), idle, total, waitMinutes

RunningOrder
  id, machineName, storeName, statusText, endsAt
```

`idle` / `total` 为 `category == 1` 汇总。`kinds`：洗衣机空闲/总数用 `idle` / `total`，烘干机、洗鞋机用 `machines` 同类汇总；总数为 0 的类不显示。各类 `waitMinutes` 为同类 `waitTime` 的最小正值。`StoreStatus.waitMinutes` 为洗衣机的等待。

## 通知

本地通知，无推送。

- 空闲提醒：按门店 + 机型手动开关，在最短等待结束前 2 分钟触发。
- 结束提醒：使用中订单自动安排，在 `endsAt` 前 1 分钟触发；已不足 1 分钟的不安排。

小组件快照：选中店的 `id/name/idle/total/waitMinutes` + `updatedAt`。不存 JWT。

## 客户端

SwiftUI，iOS 17+（`@Observable`）。单窗口：登录 / 选店 / 状态。

模块：`Auth`，`UjingClient`，`StoreSelection`，`LaundryStatus`，`WidgetSnapshot`。

权限：定位（附近列表）；Keychain；App Group（主 App + Widget Extension）。

## 小组件

WidgetKit + App Group。展示已选门店空闲数（中尺寸列表，小尺寸一家或汇总）。点进 App。可用配置 Intent 选择显示哪几家；未配置时截断已选店列表。
