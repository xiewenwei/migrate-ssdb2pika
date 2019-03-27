#!/usr/bin/env ruby

require 'optparse'
require 'redis'
require 'ssdb'

class Migration
  SCAN_LIMIT = 100

  def initialize(options)
    @options = options
  end

  def start
    setup_client(@options[:env])
    case @options[:mode]
      when 'kv'
        scan_key_values
      when 'hash'
        scan_all_hashs
      when 'zset'
        scan_all_zsets
      when 'queue'
        scan_all_queues
      else
        scan_key_values
        scan_all_hashs
        scan_all_zsets
        scan_all_queues
    end
  end

  private

  def setup_client(env)
    if env == 'qa'
      @ssdb = SSDB.new url: "ssdb://192.168.0.1:7981"
      @ssdb_redis = Redis.new url: "redis://192.168.0.1:7981"

      @pika = Redis.new(url: 'redis://192.168.0.2:7981')
    elsif env == 'production'
      @ssdb = SSDB.new url: "ssdb://192.168.1.10:7981"
      @ssdb_redis = Redis.new url: "redis://192.168.1.10:7981"

      @pika = Redis.new(url: 'redis://192.168.1.12:7981')
    else
      raise "需要指定 env 为 qa 或 production"
    end
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

def parse_options
  options = {
    env: 'qa',
    mode: 'all',
    write: 'yes'
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: bundle exec ruby migratge-ssdb.rb [options]"

    opts.on('-e', '--env environment', 'Environment (default qa)') do |value|
      options[:env] = value
    end
    opts.on('-m', '--mode mode', 'Mode (kv/hash/zset/queue default all)') do |value|
      options[:mode] = value
    end
    opts.on('-w', '--write write', 'write pika or not (yes/no)') do |value|
      options[:write] = value
    end
  end.parse!

  options
end

Migration.new(parse_options).start
