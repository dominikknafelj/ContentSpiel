module Admin
  # The editor header's two publishing parts, as Turbo Streams, for an answer
  # to a write on a published or scheduled page or post (or a block of one):
  # the "Unpublished changes" chip and the Publish changes button appear with
  # the first change and not at the next reload. A concern and a controller
  # class around it; `Admin::Publishing` is never defined (it would shadow
  # `Publishing::`).
  #
  # The mark is read fresh: a block's write sets it on the page's row, around
  # the object this request holds.
  module PublishingState
    private

    def publishing_state_streams(record)
      owner = record.is_a?(ContentBlock) ? record.owner : record
      return [] unless owner.is_a?(Page) || owner.is_a?(Post)
      return [] if owner.published_at.nil?

      owner = owner.class.find_by(id: owner.id)
      return [] unless owner

      Admin::EditorScreen::PublishingStateComponent::PARTS.keys.map do |part|
        turbo_stream.replace(Admin::EditorScreen::PublishingStateComponent::PARTS.fetch(part),
          Admin::EditorScreen::PublishingStateComponent.new(record: owner, part: part, url_options: admin_url_options))
      end
    end
  end
end
