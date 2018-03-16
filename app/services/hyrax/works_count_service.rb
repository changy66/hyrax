module Hyrax
  # Returns Works that the current user has permission to use.
  class WorksCountService < CountService
    def initialize(context, search_builder, params)
      super(context)

      @search_builder = search_builder
      @params = params
    end

    # Returns list of works
    # @param [Symbol] access :read or :edit
    # @return [Array<Hyrax::WorksCountService::SearchResultForWorkCount>] a list with documents
    def search_results_with_work_count(access)
      works = search_results(access)
      sort_column = Integer(@params[:order]['0'][:column])
      results = []

      works.documents.each do |work|
        created_date = DateTime.parse(work['system_create_dtsi']).in_time_zone.strftime("%Y-%m-%d")
        results << [work.title, created_date, 0, work['human_readable_type_tesim'][0], work['visibility_ssi']]
      end

      if @params[:order]['0'][:dir] == 'asc'
        results.sort! { |a, b| a[sort_column] <=> b[sort_column] }
      else
        results.sort! { |a, b| b[sort_column] <=> a[sort_column] }
      end

      { draw: @params[:draw],
        recordsTotal: works['response']['numFound'],
        recordsFiltered: works.documents.length,
        data: results }
    end

    def search_results(access)
      context.repository.search(builder(access))
    end

    private

      def builder(_)
        search_builder.new(context, @params)
                      .start(@params[:start])
                      .rows(@params[:length])
      end
  end
end
