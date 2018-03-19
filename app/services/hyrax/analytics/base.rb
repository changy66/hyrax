module Hyrax
  module Analytics
    # @abstract Base class for Analytics services that support statistics needs in Hyrax.
    # Implementing subclasses must define `#connection` `#remote_statistics` and `#to_graph`
    class Base
      # Establish connection with the analytics service
      def self.connection
        raise NotImplementedError, "#{self.class}#connection is unimplemented."
      end

      # Query and generate a page-level analytics report for a given date range
      # @param [DateTime] _start_date
      # @param [DateTime] _end_date
      # @param [DateTime] _page_token - It is expected that the report return batches of results if needed. The initial
      # default value is '0'
      #
      # Analytics this report is expected to return are:
      # 1. pageviews
      # 2. unique_visitors
      # 3. returning_visitors
      #
      # @return [Array]<OpenStruct> - Should contain attributes for date, pagePath, pageviews, unique_visitors and
      # returning_visitors.
      # Example: [<OpenStruct date="2018-03-15", pagePath: '/concern/generic_works/224', pageviews: '4',
      # unique_visitors: '5', returning_visitors: '3'>]
      def self.page_report(_start_date, _end_date, _page_token)
        raise NotImplementedError, "#{self.class}#page_report is unimplemented."
      end

      # Query and generate a site-level analytics report for a given date range
      # @param [DateTime] _start_date
      # @param [DateTime] _end_date
      # @param [DateTime] _page_token - It is expected that the report return batches of results if needed. The initial
      # default value is '0'
      #
      # Analytics this report is expected to return are:
      # 1. unique_visitors
      # 2. returning_visitors
      #
      # @return [Array]<OpenStruct> - Should contain attributes for date, unique_visitors and
      # returning_visitors.
      # Example: [<OpenStruct date="2018-03-15", unique_visitors: '5', returning_visitors: '3'>]
      def self.site_report(_start_date, _end_date, _page_token)
        raise NotImplementedError, "#{self.class}#site_report is unimplemented."
      end

      # Provide a listing of models to filter for in remote analytics queries
      # This allows us to make more efficient remote batch queries, ignoring paths like /catalog which might otherwise
      # return a large result set we'll need to then ignore.
      #
      # Implementing subclasses should format filter queries as needed for the given API.
      # @return [Array] - List of current models in the application.
      # Example: ['/concern/generic_work', '/concern/namespaced_works/nested_works']
      def self.filters
        Hyrax::ExposedModelsRelation.new.allowable_types.map do |klass|
          polymorphic_path(klass.new)
        end
      end
      private_class_method :filters
    end
  end
end
