
require 'migrate_ssdb2pika/version'
require 'migrate_ssdb2pika/redis_ssdb_proxy'

module MigrateSsdb2pika
  def self.new_client(*args)
    RedisSsdbProxy.new(*args)
  end
end # MigrateSsdb2pika
