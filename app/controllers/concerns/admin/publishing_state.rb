module Admin
  # The editor header's publishing chip, as a Turbo Stream, for an answer to
  # a write on a published or scheduled page or post (or a block of one): the
  # "Unpublished changes" chip, and the mark that shows the Publish changes
  # button, appear with the first change and not at the next reload. A concern
  # and a controller class around it; `Admin::Publishing` is never defined (it
  # would shadow `Publishing::`).
  #
  # ONLY THE CHIP IS SENT. The button's form is drawn with the page and never
  # replaced: it may be the form the write queue holds while the very save
  # this answers is out (`Admin::EditorScreen::PublishingStateComponent`).
  #
  # The mark is read fresh: a block's write sets it on the page's row, around
  # the object this request holds.
  module PublishingState
    private

    def publishing_state_streams(record)
      owner = record.is_a?(ContentBlock) ? record.owner : record
      return [] unless owner.is_a?(Page) || owner.is_a?(Post)

      owner = owner.class.find_by(id: owner.id)
      return [] if owner.nil?

      state = ::Publishing::State.of(owner)
      return [] if state.draft?

      [ turbo_stream.replace(Admin::EditorScreen::PublishingStateComponent::PARTS.fetch(:chip),
        Admin::EditorScreen::PublishingStateComponent.new(record: owner, part: :chip, url_options: admin_url_options, state: state)) ]
    end
  end
end
