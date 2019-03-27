
# SSDB 数据迁移 Pika 程序

## 安装

* 克隆 migratge-ssdb 项目到运行机器
* 执行 `bundle install`

## 运行方法

* `bundle exec ruby migrate_ssdb_to_pika -e [qa|production] -m kv/hash/zset/all`

如果担心执行时间过长，可以使用 `nohup` 方式执行

## 原理

直接使用 `ssdb-rb` sdk

* 通过 `scan` 遍历 key-value 数据
* 通过 `hlist` 遍历 hash 所有 name，通过 `hscan` 遍历某一个 hash 里所有 field-value
* 通过 `zlist` 遍历 zset 所有 name，通过 `zscan` 遍历某一个 zset 里所有 member-score

更改 `ssdb-rb` 代码以支持 hlist 和 hscan
