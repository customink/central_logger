# CentralLogger

Log to a central MongoDB from Rails apps.

## Usage

1. If using Bundler, add the following to your Gemfile then refresh your dependencies by executing "bundle install":

        gem "central_logger"

1. If you're just using gem:

        gem install central_logger

1. Add the following line to your ApplicationController:

        include CentralLogger::Filter

1. If using Rails 3, SKIP this step.  Otherwise, add the following to config/environment.rb:

        require 'central_logger'
        CentralLogger::Initializer.initialize_deprecated_logger(config)

1. Add mongo settings to database.yml for each environment in which you want to use the Central Logger. The central logger will also
   look for a separate central_logger.yml or mongoid.yml (if you are using mongoid) before looking in database.yml.
   In the central_logger.yml and mongoid.yml case, the settings should be defined without the 'mongo' subkey.

   database.yml:

        development:
          adapter: mysql
          database: my_app_development
          user: root
          mongo:
            database: my_app               # required (the only required setting)
            capsize: <%= 10.megabytes %>   # default: 250MB for production; 100MB otherwise
            host: localhost                # default: localhost
            port: 27017                    # default: 27017
            replica_set: true              # default: false - Adds retries for ConnectionFailure during voting for replica set master
            safe_insert: true              # default: false - Enable/Disable safe inserts (wait for insert to propagate to all nodes)
            application_name: my_app       # default: Rails.application - Only really needed for non-capistrano Rails 2 deployments. Otherwise should set automatically.

    central_logger.yml:

        development:
          database: my_app
          capsize: <%= 10.megabytes %>
          host: localhost
          port: 27017
          replica_set: true

  With that in place, a new MongoDB document (record) will be created for each request and,
  by default will record the following information: Runtime, IP Address, Request Time, Controller,
  Action, Params, Application Name and All messages sent to the logger. The structure of the Mongo document looks like this:

        {
          'action'           : action_name,
          'application_name' : application_name (rails root),
          'controller'       : controller_name,
          'ip'               : ip_address,
          'messages'         : {
                                 'info'  : [ ],
                                 'debug' : [ ],
                                 'error' : [ ],
                                 'warn'  : [ ],
                                 'fatal' : [ ]
                               },
          'params'           : { },
          'path'             : path,
          'request_time'     : date_of_request,
          'runtime'          : elapsed_execution_time_in_milliseconds,
          'url'              : full_url
        }

  Beyond that, if you want to add extra information to the base of the document
  (let's say something like user_guid on every request that it's available),
  you can just call the Rails.logger.add_metadata method on your logger like so
  (for example from a before_filter):

        # make sure we're using the CentralLogger in this environment
        if Rails.logger.respond_to?(:add_metadata)
          Rails.logger.add_metadata(:user_guid => @user_guid)
        end

## Central Log Viewer

  Please see the [central\_log\_viewer](https://github.com/customink/central_log_viewer):
  a companion web application for querying and viewing your centralized logs.

## Querying via the Rails console

And now, for a couple quick examples on getting ahold of this log data...
First, here's how to get a handle on the MongoDB from within a Rails console:

    >> db = Rails.logger.mongo_connection
    => #&lt;Mongo::DB:0x102f19ac0 @slave_ok=nil, @name="my_app" ... &gt;

    >> collection = db[Rails.logger.mongo_collection_name]
    => #&lt;Mongo::Collection:0x1031b3ee8 @name="development_log" ... &gt;

Once you've got the collection, you can find all requests for a specific user (with guid):

    >> cursor = collection.find(:user_guid => '12355')
    => #&lt;Mongo::Cursor:0x1031a3e30 ... &gt;
    >> cursor.count
    => 5

Find all requests that took more that one second to complete:

    >> collection.find({:runtime => {'$gt' => 1000}}).count
    => 3

Find all order#show requests with a particular order id (id=order_id):

    >> collection.find({"controller" => "order", "action"=> "show", "params.id" => order_id})

Find all requests with an exception that contains "RoutingError" in the message or stack trace:

    >> collection.find({"messages.error" => /RoutingError/})

Find all requests with a request_date greater than '11/18/2010 22:59:52 GMT'

    >> collection.find({:request_time => {'$gt' => Time.utc(2010, 11, 18, 22, 59, 52)}})

Copyright (c) 2009-2011 Phil Burrows and CustomInk, released under the MIT license
