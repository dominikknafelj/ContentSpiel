module Admin
  # The editor header's publishing chip, as a Turbo Stream, for an answer to
  # a write on a published or scheduled page or post (or a block of one); what
  # is sent, and why only the chip, is `Admin::Answers::PublishingStreams`'.
  # A concern and a controller class around it; `Admin::Publishing` is never
  # defined (it would shadow `Publishing::`).
  module PublishingState
    private

    # The toast of "Publish now". A scheduled record goes live as it was
    # scheduled (its copy is taken when it is scheduled; later edits are
    # unpublished changes, drafts spec §3: typing never publishes), so when it
    # has such changes the person is told that they are not on the site.
    # `was_scheduled` is read BEFORE the save: it moves `published_at`.
    def published_now_notice(record, was_scheduled:)
      current = record.class.find_by(id: record.id)
      return "Published" unless was_scheduled && current && ::Publishing::State.of(current).changes?

      I18n.t("admin.components.editor_screen.publishing.published_as_scheduled")
    end

    # The chip's stream for a write's answer (`Admin::Answers::PublishingStreams`).
    def publishing_state_streams(record) = Admin::Answers::PublishingStreams.for(record, view: view_context, url_options: admin_url_options)
  end
end
