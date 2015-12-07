module CurationConcerns::ParentContainer
  extend ActiveSupport::Concern

  included do
    helper_method :parent
  end

  # TODO: this is slow, refactor to return a Presenter (fetch from solr)
  def parent
    @parent ||= new_or_create? ? find_parent_by_id : lookup_parent_from_child
  end

  def find_parent_by_id
    ActiveFedora::Base.find(parent_id)
  end

  def lookup_parent_from_child
    if curation_concern
      # in_objects method is inherited from Hydra::PCDM::ObjectBehavior
      curation_concern.in_objects.first
    elsif @presenter

      CurationConcerns::ParentService.parent_for(@presenter.id)
    else
      raise "no child"
    end
  end

  def parent_id
    @parent_id ||= new_or_create? ? params[:parent_id] : curation_concern.generic_works.in_objects.first.id
  end

  protected

    def new_or_create?
      %w(create new).include? action_name
    end
end
