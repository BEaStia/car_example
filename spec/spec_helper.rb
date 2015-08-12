require 'rspec'
require 'eventmachine'
require 'nokogiri'
require 'em-http-request'

Dir[File.join(Dir.pwd, "./spec/parser/*_spec.rb")].each { |f| require f }

RSpec.configure do |config|
  config.mock_with :rspec
end