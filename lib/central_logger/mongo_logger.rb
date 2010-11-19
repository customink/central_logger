require 'erb'
require 'mongo'
require 'active_support'
require 'active_support/core_ext'

module CentralLogger
  class MongoLogger < ActiveSupport::BufferedLogger
    PRODUCTION_COLLECTION_SIZE = 250.megabytes
    DEFAULT_COLLECTION_SIZE = 100.megabytes

    attr_reader :db_configuration, :mongo_connection, :mongo_collection_name

    def initialize(options={})
      path = options[:path] || File.join(Rails.root, "log/#{Rails.env}.log")
      level = options[:level] || DEBUG
      super(path, level)
      internal_initialize
    rescue => e
      # in case the logger is fouled up use stdout
      puts "=> !! A connection to mongo could not be established - the logger will function like a normal ActiveSupport::BufferedLogger !!"
      puts e.message + "\n" + e.backtrace.join("\n")
    end

    def add_metadata(options={})
      if @mongo_record.present?
        options.each_pair do |key, value|
          unless [:messages, :request_time, :ip, :runtime, :application_name].include?(key.to_sym)
            @mongo_record[key] = value
          else
            raise ArgumentError, ":#{key} is a reserved key for the central logger. Please choose a different key"
          end
        end
      end
    end

    def add(severity, message = nil, progname = nil, &block)
      if @level <= severity && message.present? && @mongo_record.present?
        # remove Rails colorization to get the actual message
        message.gsub!(/(\e(\[([\d;]*[mz]?))?)?/, '').strip! if logging_colorized?
        @mongo_record[:messages][level_to_sym(severity)] << message
      end
      super
    end

    # Drop the capped_collection and recreate it
    def reset_collection
      @mongo_connection[@mongo_collection_name].drop
      create_collection
    end

    def mongoize(options={})
      @mongo_record = options.merge({
        :messages => Hash.new { |hash, key| hash[key] = Array.new },
        :request_time => Time.now.to_i,
        :application_name => @application_name
      })

      runtime = Benchmark.measure{ yield }.real
    rescue Exception => e
      add(3, e.message + "\n" + e.backtrace.join("\n"))
      # Reraise the exception for anyone else who cares
      raise e
    ensure
      # In case of exception, make sure runtime is set
      runtime ||= 0
      insert_log_record(runtime)
    end

    private
      # facilitate testing
      def internal_initialize
        configure
        connect
        check_for_collection
      end

      def configure
        default_capsize = Rails.env.production? ? PRODUCTION_COLLECTION_SIZE : DEFAULT_COLLECTION_SIZE
        user_config = YAML::load(ERB.new(IO.read(File.join(Rails.root, 'config/database.yml'))).result)[Rails.env]['mongo'] || {}
        @application_name = Rails.root.basename.to_s

        @mongo_collection_name = "#{Rails.env}_log"

        @db_configuration = {
          'host' => 'localhost',
          'port' => 27017,
          'capsize' => default_capsize}.merge(user_config)
      end

      def connect
        @mongo_connection ||= Mongo::Connection.new(@db_configuration['host'],
                                                    @db_configuration['port'],
                                                    :auto_reconnect => true).db(@db_configuration['database'])
      end

      def create_collection
        @mongo_connection.create_collection(@mongo_collection_name,
                                            {:capped => true, :size => @db_configuration['capsize']})
      end

      def check_for_collection
        # setup the capped collection if it doesn't already exist
        unless @mongo_connection.collection_names.include?(@mongo_collection_name)
          create_collection
        end
      end

      def insert_log_record(runtime)
        @mongo_record[:runtime] = (runtime * 1000).ceil
        @mongo_connection[@mongo_collection_name].insert(@mongo_record) rescue nil
      end

      def level_to_sym(level)
        case level
          when 0 then :debug
          when 1 then :info
          when 2 then :warn
          when 3 then :error
          when 4 then :fatal
          when 5 then :unknown
        end
      end

      def logging_colorized?
        # Cache it since these ActiveRecord attributes are assigned after logger initialization occurs
        @colorized ||= Object.const_defined?(:ActiveRecord) &&
        (Rails::VERSION::MAJOR >= 3 ?
          ActiveRecord::LogSubscriber.colorize_logging :
          ActiveRecord::Base.colorize_logging)
      end
  end # class MongoLogger
end
