if Rails::VERSION::MAJOR == 3
  require 'central_logger/initializer_mixin'

  class Railtie < Rails::Railtie
    include CentralLogger::InitializerMixin

    # load earlier than bootstrap.rb initializer loads the default logger.  bootstrap
    # initializer will then skip its own initialization once Rails.logger is defined
    initializer :initialize_central_logger, :before => :initialize_logger do
      app_config = Rails.application.config
      Rails.logger = config.logger = create_logger(app_config,
        ((app_config.paths['log'] rescue nil) || app_config.paths.log.to_a).first)
    end
  end
end

