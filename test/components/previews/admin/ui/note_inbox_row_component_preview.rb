module Admin
  module Ui
    # One line of Notes for you: an unread mention, a read reply, and a note on
    # a block. The rows are plain data, as `Dashboard::NotesForYou` hands them.
    class NoteInboxRowComponentPreview < ViewComponent::Preview
      def unread = render(Admin::Ui::NoteInboxRowComponent.new(row: row(unread: true)))

      def read = render(Admin::Ui::NoteInboxRowComponent.new(row: row(reason: "reply", unread: false)))

      def on_a_block
        block = ContentBlock.new(block_type: "rich_text", position: 0)
        heading = Notes::Heading::Name.new(type: "Rich text", section: nil, column: nil, words: "Our prices start at 9 euros", file_name: nil, position: 1)
        render(Admin::Ui::NoteInboxRowComponent.new(row: row(unread: true, block:, heading:)))
      end

      private

      def row(reason: "mention", unread:, block: nil, heading: nil)
        Dashboard::NotesForYou::Row.new(
          id: 1, reason:, by: User.new(id: 2, name: "Dana", email_address: "dana@example.com"), by_id: 2,
          excerpt: "Ready, Ada?", kind: "page", title: "Pricing", block:, heading:,
          route: Audit::Sentence::Route.new(:admin_page_path, [ 1 ], {}), unread:, at: 2.hours.ago, thread_id: 1
        )
      end
    end
  end
end
