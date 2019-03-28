
# 迁移 SSDB 到 Redis/Pika 工具

该 Gem 用于 迁移 SSDB 到 Redis/Pika, 包括支持双写工具和迁移历史数据工具，下面分别介绍用法。

## 1、SSDB 和 Redis/Pika 双写代理

### 使用方法

* 在目标项目（通常是 Rails 应用）引入 `migrate_ssdb2pika` gem
* 配置 SSDB 连接生成以支持双写

例如：

```ruby
  ssdb = Redis.new(host: '192.168.1.3', port: 7981)
  pika = Redis.new(host: '192.168.1.5', port: 7981)

  $ssdb = MigrateSsdb2pika.new_client(master: ssdb, slave: pika, master_is_ssdb: true)
```

$ssdb 就是支持双写的 client connection

### 特别注意事项

SSDB 使用 zclear 方法删除 zset 的 key，而 Redis/Pika 并不支持 zclear 方法，所以需要特殊处理。

如果原来有直接使用 zclear 的话，需要改写成如下的形式：

```ruby
  if $ssdb.respond_to? :clear_zset
    $ssdb.clear_zset key
  else
    $ssdb.del key
  end
```

迁移完成后改为只使用 `$ssdb.del key` 即可。

## 2、迁移历史数据工具

### 安装

* 克隆 migrate-ssdb2pika 项目到运行机器
* 执行 `bundle install`

### 运行方法

```shell
bin/ssdb2pika --ssdb_host=xxx --ssdb_port=xxx \
  --pika_host=xxx --pika_port=xx \
  -m <kv|hash|zset|queue|all>
```

例如：

```shell
bin/ssdb2pika --ssdb_host=192.168.0.10 --ssdb_port=7981 \
--pika_host=192.168.0.12 --pika_port=7981 -m all
```

如果担心执行时间过长，可以使用 `nohup` 方式执行。

```shell
nohup bin/ssdb2pika --ssdb_host=192.168.0.10 --ssdb_port=7981 \
--pika_host=192.168.0.12 --pika_port=7981 -m all &
```

### 原理

直接使用 `ssdb-rb` sdk

* 通过 `scan` 遍历 key-value 数据
* 通过 `hlist` 遍历 hash 所有 name，通过 `hscan` 遍历某一个 hash 里所有 field-value
* 通过 `zlist` 遍历 zset 所有 name，通过 `zscan` 遍历某一个 zset 里所有 member-score
* 通过 `qlist` 遍历 queue 所有 name

更改 `ssdb-rb` 代码以支持 hlist/hscan/qlist/qrange
