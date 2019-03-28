# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'migrate_ssdb2pika/version'

Gem::Specification.new do |spec|
  spec.name          = "migrate-ssdb2pika"
  spec.version       = MigrateSsdb2pika::VERSION
  spec.authors       = ["Vincent Xie"]
  spec.email         = ["xiewenwei@gmail.com"]

  spec.summary       = %q{迁移 SSDB 数据到 Redis 或 Pika 工具集}
  spec.description   = %q{迁移 SSDB 数据到 Redis 或 Pika 工具集，提供迁移过程中的双写工具类和迁移历史数据工具}
  spec.homepage      = "http://github.com/xiewenwei/migrate-ssdb2pika.git"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = ["ssdb2pika"]
  spec.require_paths = ["lib"]

  spec.add_dependency "redis", ">= 3"

  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
