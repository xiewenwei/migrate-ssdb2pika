
```ruby
  ssdb = Redis.new(host: '192.168.1.3', port: 7981)
  pika = Redis.new(host: '192.168.1.5', port: 7981)

  $ssdb = RedisSsdbProxy.new(master: ssdb, slave: pika, master_is_ssdb: true)
```

注意如果原来有直接使用 zclear 的话，需要改写成如下的形式

```ruby
  if $ssdb.respond_to? :clear_zset
    $ssdb.clear_zset key
  else
    $ssdb.del key
  end
```
