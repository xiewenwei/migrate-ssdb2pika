
require 'redis'
require 'ssdb'

module MigrateSsdb2pika
  class Migration
    SCAN_LIMIT = 100

    def initialize(options)
      @options = options
    end

    def start
      setup_client
      log_message("start")
      case @options[:mode]
        when 'kv'
          scan_key_values
          log_message("scan_key_values done")
        when 'hash'
          scan_all_hashs
          log_message("scan_all_hashs done")
        when 'zset'
          scan_all_zsets
          log_message("scan_all_zsets done")
        when 'queue'
          scan_all_queues
          log_message("scan_all_queues done")
        else
          scan_key_values
          log_message("scan_key_values done")
          scan_all_hashs
          log_message("scan_all_hashs done")
          scan_all_zsets
          log_message("scan_all_zsets done")
          scan_all_queues
          log_message("scan_all_queues done")
      end
    end

    private

    def log_message(msg)
      puts "[#{Time.now.to_s}] #{msg}"
    end

    def setup_client
      @ssdb = SSDB.new url: "ssdb://#{@options[:ssdb_host]}:#{@options[:ssdb_port]}"
      @ssdb_redis = Redis.new url: "redis://#{@options[:ssdb_host]}:#{@options[:ssdb_port]}"
      @pika = Redis.new url: "redis://#{@options[:pika_host]}:#{@options[:pika_port]}"
    end

    # key-value scan
    def scan_key_values
      count = 0
      key_start = ''
      while true
        entries = @ssdb.scan(key_start, '', limit: SCAN_LIMIT)
        count += 1
        puts "scan_key_values #{count} name_start: #{key_start}"
        if entries.size == 0
          break
        end

        array = []
        entries.each do |key, value|
          array << key
          array << value
        end

        if @options[:write] == 'yes'
          @pika.mset *array
        else
          puts "array size #{array.size}"
        end
        key_start = entries.last[0]
      end
    end

    # hash hlist
    def scan_all_hashs(limit: SCAN_LIMIT)
      count = 0
      name_start = ''
      while true
        names = @ssdb.hlist(name_start, '', limit: limit)
        count += 1
        puts "scan_all_hashs #{count} name_start: #{name_start}"
        if names.size == 0
          break
        end

        hash_len = []
        @ssdb_redis.pipelined do |redis|
          names.each do |name|
            hash_len << redis.hlen(name)
          end
        end

        short_names = []
        long_names = []
        names.each_with_index do |name, index|
          if hash_len[index].value.to_i > 1000
            long_names << name
          else
            short_names << name
          end
        end

        scan_group_hashs(short_names)

        long_names.each { |name| scan_one_hash(name) }

        name_start = names.last
      end
    end

    # hash hscan
    def scan_group_hashs(names)
      # 批量读取
      result = []
      @ssdb_redis.pipelined do |redis|
        names.each do |name|
          result << redis.hgetall(name)
        end
      end
      # 批量写入
      if @options[:write] == 'yes'
        @pika.pipelined do |redis|
          names.each_with_index do |name, index|
            array = result[index].value.to_a
            if array && array.size > 0
              array.flatten!
              redis.hmset name, *array
            end
          end
        end
      else
        puts "result size #{result.size}"
      end
    end

    # hash hscan
    def scan_one_hash(name)
      key_start = ''
      while true
        entries = @ssdb.hscan(name, key_start, '', limit: 1000)

        if entries.size == 0
          break
        end

        array = []
        entries.each do |key, value|
          array << key
          array << value
        end

        if @options[:write] == 'yes'
          @pika.hmset name, *array
        else
          puts "#{name} array size #{array.size}"
        end

        key_start = entries.last[0]
      end
    end

    # zset zlist
    def scan_all_zsets(limit: SCAN_LIMIT)
      count = 0
      name_start = ''
      while true
        names = @ssdb.zlist(name_start, '', limit: limit)

        count += 1
        puts "scan_all_zsets #{count} name_start: #{name_start}"

        if names.size == 0
          break
        end

        zset_len = []
        @ssdb_redis.pipelined do |redis|
          names.each do |name|
            zset_len << redis.zcard(name)
          end
        end

        short_names = []
        long_names = []
        names.each_with_index do |name, index|
          if zset_len[index].value.to_i > 1000
            long_names << name
          else
            short_names << name
          end
        end

        scan_group_zsets(short_names)

        long_names.each { |name| scan_one_zset(name) }

        name_start = names.last
      end
    end

    # zset zscan
    def scan_group_zsets(names)
      # 批量读取
      result = []
      @ssdb_redis.pipelined do |redis|
        names.each do |name|
          result << redis.zrange(name, 0, -1, with_scores: true)
        end
      end
      # 批量写入
      if @options[:write] == 'yes'
        @pika.pipelined do |redis|
          names.each_with_index do |name, index|
            array = result[index].value.to_a
            if array && array.size > 0
              array.each { |pair| pair.reverse! }
              redis.zadd name, array
            end
          end
        end
      else
        puts "result size #{result.size}"
      end
    end

    # zset zscan
    def scan_one_zset(name)
      score_start = ''
      while true
        entries = @ssdb.zscan(name, score_start, '', limit: SCAN_LIMIT)
        if entries.size == 0
          break
        end

        array = entries.map {|key, value| [value, key] }

        if @options[:write] == 'yes'
          @pika.zadd name, array
        else
          puts "#{name} array size #{array.size}"
        end

        score_start = entries.last[1].to_i + 1
      end
    end

    # queue qlist
    def scan_all_queues
      count = 0
      name_start = ''
      while true
        names = @ssdb.qlist(name_start, '', limit: 1000)
        count += 1
        puts "scan_all_queues #{count} name_start: #{name_start}"
        if names.size == 0
          break
        end

        names.each_with_index do |name, index|
          scan_one_queue(name)
          if index % 10 == 0
            puts "process #{name} #{index}"
          end
        end
        name_start = names.last
      end
    end

    # queue qrange
    def scan_one_queue(name)
      array = @ssdb.qrange(name, 0, -1)
      if array && array.size > 0
        if @options[:write] == 'yes'
          array.each do |item|
            @pika.lpush name, item
          end
        else
          puts "#{name} array size #{array.size}"
        end
      end
    end
  end
end
