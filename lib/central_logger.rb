$:.unshift File.dirname(__FILE__)

require 'mongo'
require 'central_logger/mongo_logger'
require 'central_logger/filter'
require 'central_logger/initializer'
require 'central_logger/railtie' if defined?(Rails::Railtie)

