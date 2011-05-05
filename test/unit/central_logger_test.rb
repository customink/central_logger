require 'test_helper'
require 'central_logger/mongo_logger'
require 'tempfile'
require 'pathname'

# test the basic stuff
class CentralLogger::MongoLoggerTest < Test::Unit::TestCase
  extend LogMacros

  EXCEPTION_MSG = "Foo"

  context "A CentralLogger::MongoLogger" do
    setup do
      # Can use different configs, but most tests use database.yml
      FileUtils.cp(File.join(SAMPLE_CONFIG_DIR, DEFAULT_CONFIG),  CONFIG_DIR)
    end

    context "in instantiation" do
      setup do
        CentralLogger::MongoLogger.any_instance.stubs(:internal_initialize).returns(nil)
        CentralLogger::MongoLogger.any_instance.stubs(:disable_file_logging?).returns(false)
        @central_logger = CentralLogger::MongoLogger.new
      end

      context "during configuration when using a separate " + LOGGER_CONFIG do
        setup do
          setup_for_config(LOGGER_CONFIG)
        end

        should_use_database_name_in_config

        teardown do
          teardown_for_config(LOGGER_CONFIG)
        end
      end

      context "during configuration when using a separate " + MONGOID_CONFIG do
        setup do
          setup_for_config(MONGOID_CONFIG)
        end

        should_use_database_name_in_config

        teardown do
          teardown_for_config(MONGOID_CONFIG)
        end
      end

      # this test will work without the --auth mongod arg
      context "upon connecting with authentication settings" do
        setup do
          setup_for_config(DEFAULT_CONFIG_WITH_AUTH, DEFAULT_CONFIG)
          create_user
        end

        should "authenticate with the credentials in the configuration" do
          @central_logger.send(:connect)
          assert @central_logger.authenticated?
        end

        teardown do
          # config will be deleted by outer teardown
          remove_user
        end
      end

      context "after configuration" do
        setup do
          @central_logger.send(:configure)
        end

        should "set the default host, port, and capsize if not configured" do
          assert_equal 'localhost', @central_logger.db_configuration['host']
          assert_equal 27017, @central_logger.db_configuration['port']
          assert_equal CentralLogger::MongoLogger::DEFAULT_COLLECTION_SIZE, @central_logger.db_configuration['capsize']
        end

        should "set the mongo collection name depending on the Rails environment" do
          assert_equal "#{Rails.env}_log", @central_logger.mongo_collection_name
        end

        should "set the application name when specified in the config file" do
          assert_equal "central_foo", @central_logger.instance_variable_get(:@application_name)
        end

        should "set safe insert when specified in the config file" do
          assert @central_logger.instance_variable_get(:@safe_insert)
        end

        should "use the database name in the config file" do
          assert_equal "system_log", @central_logger.db_configuration['database']
        end

        context "upon connecting to an empty database" do
          setup do
            @central_logger.send(:connect)
            common_setup
            @collection.drop
          end

          should "expose a valid mongo connection" do
            assert_instance_of Mongo::DB, @central_logger.mongo_connection
          end

          should "not authenticate" do
            assert !@central_logger.authenticated?
          end

          should "create a capped collection in the database with the configured size" do
            @central_logger.send(:check_for_collection)
            assert @con.collection_names.include?(@central_logger.mongo_collection_name)
            # new capped collections are X MB + 5888 bytes, but don't be too strict in case that changes
            assert @collection.stats["storageSize"] < CentralLogger::MongoLogger::DEFAULT_COLLECTION_SIZE + 1.megabyte
          end
        end
      end
    end

    context "after instantiation" do
      setup do
        @central_logger = CentralLogger::MongoLogger.new
        common_setup
        @central_logger.reset_collection
      end

      context "upon insertion of a log record when active record is not used" do
        # mock ActiveRecord has not been included
        setup do
          log("Test")
        end

        should_contain_one_log_record

        should "allow recreation of the capped collection to remove all records" do
          @central_logger.reset_collection
          assert_equal 0, @collection.count
        end
      end

      context "upon insertion of a colorized log record when ActiveRecord is used" do
        setup do
          @log_message = "TESTING"
          require_bogus_active_record
          log("\e[31m #{@log_message} \e[0m")
        end

        should "detect logging is colorized" do
          assert @central_logger.send(:logging_colorized?)
        end

        should_contain_one_log_record

        should "strip out colorization from log messages" do
          assert_equal 1, @collection.find({"messages.debug" => @log_message}).count
        end
      end

      should "add application metadata to the log record" do
        options = {"application" => self.class.name}
        log_metadata(options)
        assert_equal 1, @collection.find({"application" => self.class.name}).count
      end

      should "not raise an exception when bson-unserializable data is logged in the :messages key" do
        log(Tempfile.new("foo"))
        assert_equal 1, @collection.count
      end

      should "not raise an exception when bson-unserializable data is logged in the :params key" do
        log_params({:foo => Tempfile.new("bar")})
        assert_equal 1, @collection.count
      end

      context "when an exception is raised" do
        should "log the exception" do
          assert_raise(RuntimeError, EXCEPTION_MSG) {log_exception(EXCEPTION_MSG)}
          assert_equal 1, @collection.find_one({"messages.error" => /^#{EXCEPTION_MSG}/})["messages"]["error"].count
        end
      end
    end

    context "logging at INFO level" do
      setup do
        @central_logger = CentralLogger::MongoLogger.new(:level => CentralLogger::MongoLogger::INFO)
        common_setup
        @central_logger.reset_collection
        log("INFO")
      end

      should_contain_one_log_record

      should "not log DEBUG messages" do
        assert_equal 0, @collection.find_one({}, :fields => ["messages"])["messages"].count
      end
    end
    teardown do
      file = File.join(CONFIG_DIR, DEFAULT_CONFIG)
      File.delete(file) if File.exist?(file)
    end
  end

  context "A CentralLogger::MongoLogger without file logging" do
    setup do
      FileUtils.cp(File.join(SAMPLE_CONFIG_DIR, DEFAULT_CONFIG_WITH_NO_FILE_LOGGING),  File.join(CONFIG_DIR, DEFAULT_CONFIG))
      @log_file = Pathname.new('log.out')
      FileUtils.touch(@log_file)
    end

    context "in instantiation" do
      should "not call super in the initialize method" do
        CentralLogger::MongoLogger.any_instance.expects(:open).never # Stubbing out super doesn't work, so we use this side effect instead.
        CentralLogger::MongoLogger.new
      end

      should "set level" do
        level = stub('level')
        logger = CentralLogger::MongoLogger.new(:level => level)
        assert_equal level, logger.level
      end
    end

    context "after instantiation" do
      context "upon insertion of a log record" do
        setup do
          @central_logger = CentralLogger::MongoLogger.new(:path => @log_file)
          log("Test")
        end

        should "not log the record to a file" do
          assert_equal '', open(@log_file).read
        end
      end
    end

    teardown do
      file = File.join(CONFIG_DIR, DEFAULT_CONFIG)
      File.delete(file) if File.exist?(file)
      File.delete(@log_file)
    end
  end
end
