
# 不支持 Set，不支持类型不一致的 Redis::Object

module RedisSsdbProxy
  class Client
    attr_accessor :master, :slave

    def initialize(master: nil, slave: nil, master_is_ssdb: true)
      self.master = master
      self.slave = slave

      # 植入 ssdb? 方法
      if master_is_ssdb
        master.define_singleton_method(:ssdb?) { true }
      else
        master.define_singleton_method(:ssdb?) { false }
      end
    end

    def clear_zset(key)
      if master.ssdb?
        master.zclear key
        slave.del key
      else
        master.del key
        slave.zclear key
      end
    end

    class << self
      private

      def send_to_slave(command)
        class_eval <<-EOS
          def #{command}(*args, &block)
            slave.#{command}(*args, &block)
          end
        EOS
      end

      def send_to_master(command)
        class_eval <<-EOS
          def #{command}(*args, &block)
            master.#{command}(*args, &block)
          end
        EOS
      end

      def send_to_both(command)
        class_eval <<-EOS
          def #{command}(*args, &block)
            slave.#{command}(*args, &block)
            master.#{command}(*args, &block)
          end
        EOS
      end
    end

    send_to_master :dbsize
    send_to_master :exists
    send_to_master :get
    send_to_master :getbit
    send_to_master :getrange
    send_to_master :hexists
    send_to_master :hget
    send_to_master :hgetall
    send_to_master :hkeys
    send_to_master :hlen
    send_to_master :hmget
    send_to_master :hvals
    send_to_master :keys
    send_to_master :lindex
    send_to_master :llen
    send_to_master :lrange
    send_to_master :mget
    send_to_master :randomkey
    send_to_master :scard
    send_to_master :sdiff
    send_to_master :sinter
    send_to_master :sismember
    send_to_master :smembers
    send_to_master :sort
    send_to_master :srandmember
    send_to_master :strlen
    send_to_master :sunion
    send_to_master :ttl
    send_to_master :type
    send_to_master :zcard
    send_to_master :zcount
    send_to_master :zrange
    send_to_master :zrangebyscore
    send_to_master :zrank
    send_to_master :zrevrange
    send_to_master :zscore

    # all write opreate send to master slave both
    def method_missing(name, *args, &block)
      if master.respond_to?(name)
        self.class.send(:send_to_both, name)
        slave.send(name, *args, &block)
        master.send(name, *args, &block)
      else
        super
      end
    end
  end # Client

  def self.new(*args)
    Client.new(*args)
  end

end # RedisSsdbProxy
