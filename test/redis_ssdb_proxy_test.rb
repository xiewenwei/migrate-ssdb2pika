require 'test_helper'

class RedisSsdbProxyTest < Minitest::Test
  def setup
    @ssdb = Minitest::Mock.new
    @pika = Minitest::Mock.new
    @ssdb.expect :define_singleton_method, true, [Symbol]
    @ssdb.expect :ssdb?, true
    @redis = MigrateSsdb2pika.new_client master: @ssdb, slave: @pika, master_is_ssdb: true
  end

  def test_double_write
    @ssdb.expect :set, true, [String, String]
    @pika.expect :set, true, [String, String]
    @redis.set "mykey", "myvalue"
    assert @ssdb.ssdb?
    @ssdb.verify
    @pika.verify
  end

  def test_read_master
    @ssdb.expect :get, "ss", [String]
    @pika.expect :get, "pk", [String]
    assert_equal "ss", @redis.get("my")
  end
end
