module Hyrax
  # Cache page and site-wide analytics
  # This is called by `rake hyrax:stats:import_analytics`
  class AnalyticsImporter
    attr_reader :start_date, :end_date

    def initialize(start_date:, end_date = 1.day.ago, options = {})
      if options[:verbose]
        stdout_logger = Logger.new(STDOUT)
        stdout_logger.level = Logger::INFO
        Rails.logger.extend(ActiveSupport::Logger.broadcast(stdout_logger))
      end

      @logging = options[:logging]
      @delay_secs = options[:delay_secs].to_f
      @number_of_tries = options[:number_of_retries].to_i + 1

      @start_date = start_date
      @end_date = end_date
    end
  end

  def import_page_stats(page_token='0')
    results = analytics_service.page_report(start_date, end_date, page_token)
    results.each do |result|
      create_or_update(result)
    end
    # TODO: persist page stats...
    if results[:nextPageToken]
      import_page_stats(start_date, end_date, results[:nextPageToken])
    end

  end

  def import_site_stats(page_token='0')
    results = analytics_service.site_report(start_date, end_date, page_token)
    results.each do |result|
      create_or_update(result)
    end
    if results[:nextPageToken] #TODO: can Matomo pass this along too? Or do we need to coerce?
      import_site_stats(start_date, end_date, results[:nextPageToken])
    end
  end

  def create_or_update(result)

  end

  private
  def analytics_service
    @analytics_service ||= case Hyrax.config.analytics
    when 'matomo'
      Hyrax::Analytics::Matomo
    when 'google' || true
      Hyrax::Analytics::GoogleAnalytics
    end
  end
end
