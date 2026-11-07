module Admin
  module DashboardScreen
    # One line of "What changed recently": the actor's mark
    # (`Admin::Ui::ActorAvatarComponent`, the audit log's too), one sentence
    # -- "<name> published “<title>”", the title a link to the record's
    # editor -- a status chip when the record is not Live, and a relative time. A
    # coalesced burst of edits shows the time it last extended, with the
    # whole span as its tooltip.
    #
    # A change through a token names the token's *user*, with the user's own
    # avatar, and says "via <token name>" beside an MCP chip. The name
    # is the one recorded on the event (the sentence's actor), escaped like any
    # text; no part of the token's value is ever rendered, and the row does
    # not even carry the token. The wording is the audit log's own
    # (`Admin::AuditScreen::SentenceComponent` over `Audit::Sentence`).
    # Everything comes from a `Dashboard::Activity::Row` (record, user and time
    # already loaded), so a row never queries.
    class ActivityRowComponent < Admin::AdminComponent
      def initialize(row:)
        @row = row
      end

      def sentence = row.sentence

      def via_token? = sentence.actor.via_label.present?

      def channel = row.event.channel

      def record = row.record

      # Pages and posts have a publish state; an image has none.
      def status? = !record.is_a?(Media::Asset)

      # A burst's tooltip: when it began, and the time it last extended.
      def span_title
        return unless row.span_end

        t(".span", from: I18n.l(row.at.in_time_zone, format: :"admin.datetime"), to: I18n.l(row.span_end.in_time_zone, format: :"admin.time"))
      end

      def shown_at = row.span_end || row.at

      private

      attr_reader :row

      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
