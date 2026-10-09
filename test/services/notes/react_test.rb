require "test_helper"

class Notes::ReactTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Shipped") }.record
    @note = @thread.first_message
  end

  def react(emoji, as_user: users(:reader), to: @note, on: true) = as(as_user) { Notes::React.call(to, emoji: emoji, on: on) }

  test "a reader reacts, and takes the reaction back" do
    assert react("👍").ok?
    assert_equal [ [ users(:reader).id, "👍" ] ], @note.reactions.pluck(:user_id, :emoji)

    assert react("👍", on: false).ok?
    assert_empty @note.reactions.reload
  end

  # Not a blind toggle: a request sent twice, or a press in a tab that had not
  # seen the reaction given in another, ends where the person meant.
  test "asking for what is already so succeeds, writes nothing and signals nobody" do
    assert react("👍").ok?
    row = @note.reactions.sole

    assert_no_changes -> { Notes::Reaction.pluck(:id, :updated_at) } do
      assert_no_broadcasts(Notes::Signals.record_stream("Page", @page.id)) { assert react("👍").ok? }
    end
    assert_equal row, @note.reactions.sole

    assert react("👍", on: false).ok?
    assert_no_broadcasts(Notes::Signals.record_stream("Page", @page.id)) { assert react("👍", on: false).ok? }
    assert_empty @note.reactions.reload
  end

  test "a resolved thread takes no reaction and gives none back: a sentence, nothing written, no signal" do
    react("👍")
    as(users(:two)) { assert Notes::Resolve.call(@thread).ok? }
    refused = [ I18n.t("admin.notes.errors.resolved") ]

    assert_no_broadcasts(Notes::Signals.record_stream("Page", @page.id)) do
      [ react("🎉"), react("👍", on: false), react("👍", as_user: users(:two)) ].each do |result|
        assert_equal [ refused, false ], [ result.errors, result.denied? ]
      end
    end
    assert_equal [ [ users(:reader).id, "👍" ] ], Notes::Reaction.pluck(:user_id, :emoji)

    as(users(:two)) { assert Notes::Reopen.call(@thread).ok? }
    assert react("🎉").ok?
  end

  test "several people and several emoji; a reaction tells nobody and is not audited" do
    assert_no_difference [ -> { Audit::Event.count }, -> { Notes::Delivery.count } ] do
      react("👍")
      react("🎉")
      react("👍", as_user: users(:two))
    end

    assert_equal({ "👍" => 2, "🎉" => 1 }, @note.reactions.unscope(:order).group(:emoji).count)
  end

  test "only the offered set is accepted, and a stranger is refused" do
    assert_not react("<script>").ok?
    assert_not react("").ok?
    assert_not react("👍👍").ok?
    assert_predicate react("👍", as_user: User.create!(email_address: "stranger@example.com", password: "a-long-password-1")), :denied?
    assert_equal 0, Notes::Reaction.count
  end

  test "the record refuses an emoji outside the set too" do
    reaction = Notes::Reaction.new(message: @note, user: users(:reader), emoji: "<b>")

    assert_not reaction.valid?
    assert Notes::Reaction.new(message: @note, user: users(:reader), emoji: Notes::EMOJI.last).valid?
  end

  test "a reaction writes neither the thread's date nor the page" do
    before = [ @thread.reload.last_message_at, @thread.updated_at, @page.reload.updated_at, @note.reload.updated_at ]

    travel_to(1.minute.from_now) { react("👍") }

    assert_equal before, [ @thread.reload.last_message_at, @thread.updated_at, @page.reload.updated_at, @note.reload.updated_at ]
  end

  test "reactions go with their message, their user and their record" do
    user = User.create!(email_address: "fan@example.com", password: "a-long-password-1")
    AccessControl::Membership.create!(group: access_control_groups(:read_only), user: user)
    react("👍", as_user: user)
    react("👍")

    user.destroy!
    assert_equal 1, Notes::Reaction.count
    Notes::Remove.call(@page)
    assert_equal 0, Notes::Reaction.count
  end

  test "deleting a message takes its reactions with it" do
    reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "Seen") }.record
    react("👀", to: reply)

    assert as(users(:reader)) { Notes::DeleteMessage.call(reply) }.ok?
    assert_equal 0, Notes::Reaction.count
  end

  # Like every notes write on an existing thread: the container's row lock is
  # the first statement of the transaction, before any notes row is read.
  test "the page's row is locked before anything is read or written" do
    statements = capture_sql { react("👍") }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/) }

    assert lock, statements.join("\n")
    assert_operator lock, :<, statements.index { |sql| sql.include?('"note_reactions"') }
    assert_operator lock, :<, statements.index { |sql| sql.match?(/FROM "note_threads".*FOR UPDATE/) }
  end

  test "on a trashed record, a thread that went or a message that went, the note is gone and nothing is written" do
    gone = I18n.t("admin.notes.errors.gone.note")
    reply = as(users(:reader)) { Notes::Reply.call(@thread, body: "Seen") }.record
    Notes::Message.where(id: reply.id).delete_all
    assert_equal [ gone ], react("👍", to: reply).errors

    Page.where(id: @page.id).update_all(trashed_at: Time.current)
    assert_equal [ gone ], react("👍").errors
    Page.where(id: @page.id).update_all(trashed_at: nil)

    Notes::Thread.where(id: @thread.id).delete_all
    result = react("👍")
    assert_equal [ [ gone ], false ], [ result.errors, result.denied? ]
    assert_equal [ gone ], react("👍", to: Notes::Message.new(body: "x")).errors
    assert_equal 0, Notes::Reaction.count
  end
end
