# rubocop:disable Metrics/ClassLength
module Hyrax
  module Actors
    # Actions are decoupled from controller logic so that they may be called from a controller or a background job.
    class FileSetActor
      include Lockable
      attr_reader :file_set, :user, :attributes

      def initialize(file_set, user)
        @file_set = file_set
        @user = user
      end

      # @!group Asynchronous Operations

      # Spawns asynchronous IngestJob unless ingesting from URL
      # Called from FileSetsController, AttachFilesToWorkJob, IngestLocalFileJob, ImportUrlJob
      # @param [Hyrax::UploadedFile, File] file the file uploaded by the user
      # @param [Symbol, #to_s] relation
      # @return [IngestJob, FalseClass] false on failure, otherwise the queued job
      def create_content(file, relation = :original_file, from_url: false)
        # If the file set doesn't have a title or label assigned, set a default.
        file_set.label ||= label_for(file)
        file_set.title = [file_set.label] if file_set.title.blank?

        persister = Valkyrie::MetadataAdapter.find(:indexing_persister).persister
        # Need to save to get an id
        saved_file = persister.save(resource: file_set)
        return unless saved_file

        if from_url
          # If ingesting from URL, don't spawn an IngestJob; instead
          # reach into the FileActor and run the ingest with the file instance in
          # hand. Do this because we don't have the underlying UploadedFile instance
          file_actor = build_file_actor(relation)
          file_actor.ingest_file(wrapper!(file: file, relation: relation))
          # Copy visibility and permissions from parent (work) to
          # FileSets even if they come in from BrowseEverything
          VisibilityCopyJob.perform_later(saved_file.parent)
          InheritPermissionsJob.perform_later(saved_file.parent)
        else
          IngestJob.perform_later(wrapper!(file: file, relation: relation))
        end
      end

      # Spawns asynchronous IngestJob with user notification afterward
      # @param [Hyrax::UploadedFile, File, ActionDigest::HTTP::UploadedFile] file the file uploaded by the user
      # @param [Symbol, #to_s] relation
      # @return [IngestJob] the queued job
      def update_content(file, relation = :original_file)
        IngestJob.perform_later(wrapper!(file: file, relation: relation), notification: true)
      end

      # @!endgroup

      # Adds the appropriate metadata, visibility and relationships to file_set
      # @note In past versions of Hyrax this method did not perform a save because it is mainly used in conjunction with
      #   create_content, which also performs a save.  However, due to the relationship between Hydra::PCDM objects,
      #   we have to save both the parent work and the file_set in order to record the "metadata" relationship between them.
      # @param [Hash] file_set_params specifying the visibility, lease and/or embargo of the file set.
      #   Without visibility, embargo_release_date or lease_expiration_date, visibility will be copied from the parent.
      def create_metadata(file_set_params = {})
        file_set.apply_depositor_metadata(user)
        now = TimeService.time_in_utc
        file_set.date_uploaded = now
        file_set.date_modified = now
        file_set.creator = [user.user_key]
        if assign_visibility?(file_set_params)
          env = Actors::Environment.new(file_set, nil, ability, file_set_params)
          CurationConcern.file_set_create_actor.create(env)
        end
        yield(file_set) if block_given?
      end

      # Adds a FileSet to the work using ore:Aggregations.
      # Locks to ensure that only one process is operating on the list at a time.
      def attach_to_work(work, file_set_params = {})
        acquire_lock_for(work.id) do
          # Ensure we have an up-to-date copy of the members association, so that we append to the end of the list.
          work.reload if work.persisted?
          file_set.visibility = work.visibility unless assign_visibility?(file_set_params)
          work.member_ids += [file_set.id]
          work.representative = file_set if work.representative_id.blank?
          work.thumbnail = file_set if work.thumbnail_id.blank?
          # Save the work so the association between the work and the file_set is persisted (head_id)
          # NOTE: the work may not be valid, in which case this save doesn't do anything.
          persister.save(resource: work)
          Hyrax.config.callback.run(:after_create_fileset, file_set, user)
        end
      end
      alias attach_file_to_work attach_to_work
      deprecation_deprecate attach_file_to_work: "use attach_to_work instead"

      # @param [String] revision_id the revision to revert to
      # @param [Symbol, #to_sym] relation
      # @return [Boolean] true on success, false otherwise
      def revert_content(revision_id, relation = :original_file)
        return false unless build_file_actor(relation).revert_to(revision_id)
        Hyrax.config.callback.run(:after_revert_content, file_set, user, revision_id)
        true
      end

      def update_metadata(attributes)
        env = Actors::Environment.new(file_set, nil, ability, attributes)
        CurationConcern.file_set_update_actor.update(env)
      end

      def destroy
        unlink_from_work
        file_set.destroy
        Hyrax.config.callback.run(:after_destroy, file_set.id, user)
      end

      class_attribute :file_actor_class
      self.file_actor_class = Hyrax::Actors::FileActor

      private

        def persister
          Valkyrie::MetadataAdapter.find(:indexing_persister).persister
        end

        def ability
          @ability ||= ::Ability.new(user)
        end

        def build_file_actor(relation)
          file_actor_class.new(file_set, relation, user)
        end

        # uses create! because object must be persisted to serialize for jobs
        def wrapper!(file:, relation:)
          JobIoWrapper.create_with_varied_file_handling!(user: user, file: file, relation: relation, file_set: file_set)
        end

        # For the label, use the original_filename or original_name if it's there.
        # If the file was imported via URL, parse the original filename.
        # If all else fails, use the basename of the file where it sits.
        # @note This is only useful for labeling the file_set, because of the recourse to import_url
        def label_for(file)
          if file.is_a?(Hyrax::UploadedFile) # filename not present for uncached remote file!
            file.uploader.filename.present? ? file.uploader.filename : File.basename(Addressable::URI.parse(file.file_url).path)
          elsif file.respond_to?(:original_name) # e.g. Hydra::Derivatives::IoDecorator
            file.original_name
          elsif file_set.import_url.present?
            # This path is taken when file is a Tempfile (e.g. from ImportUrlJob)
            File.basename(Addressable::URI.parse(file_set.import_url).path)
          else
            File.basename(file)
          end
        end

        def assign_visibility?(file_set_params = {})
          !((file_set_params || {}).keys.map(&:to_s) & %w[visibility embargo_release_date lease_expiration_date]).empty?
        end

        def unlink_from_work
          work = file_set.parent
          return unless work && (work.thumbnail_id == file_set.id || work.representative_id == file_set.id)
          # Must clear the thumbnail_id and representative_id fields on the work and force it to be re-solrized.
          # Although ActiveFedora clears the children nodes it leaves those fields in Solr populated.
          work.thumbnail = nil if work.thumbnail_id == file_set.id
          work.representative = nil if work.representative_id == file_set.id
          work.save!
        end
    end
  end
end
# rubocop:enable Metrics/ClassLength
