require "test_helper"

class Editing::HoldsTest < ActiveSupport::TestCase
  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    @olga = users(:one)
    @dana = users(:two)
    @now = Time.current.change(usec: 0)
  end

  def hold(subject, user, tab, at: @now) = Editing::Reservation.claim(subject:, record: @page, user:, tab:, now: at)

  def holds(viewer, tab, at: @now) = Editing::Holds.on(@page, viewer:, tab:, now: at)

  test "of answers the live reservation and other the one that is not mine in this tab" do
    hold(@block, @dana, B)
    h = holds(@olga, A)
    assert_equal @dana.id, h.of(@block).user_id
    assert_equal @dana.id, h.other(@block).user_id
    assert_not h.own_user?(h.of(@block))
    assert h.any?
    assert_nil h.of(@page)
  end

  test "my hold in my tab is not other; in another tab of mine it is, and it is still mine as a person" do
    hold(@block, @olga, A)
    assert_nil holds(@olga, A).other(@block)
    assert_equal @olga.id, holds(@olga, A).of(@block).user_id

    elsewhere = holds(@olga, B)
    assert_equal A, elsewhere.other(@block).tab
    assert elsewhere.own_user?(elsewhere.other(@block))
  end

  test "with no tab every hold is other" do
    hold(@block, @olga, A)
    assert holds(@olga, nil).other(@block)
  end

  test "an expired row is nobody's" do
    hold(@block, @dana, B)
    assert holds(@olga, A, at: @now + Editing::HOLD - 0.001).of(@block)
    assert_not holds(@olga, A, at: @now + Editing::HOLD).any?
  end

  test "a request is carried with its requester" do
    hold(@block, @olga, A)
    Editing::Reservation.request(subject: @block, by: @dana, tab: B, now: @now + 1)
    row = holds(@olga, A, at: @now + 2).of(@block)
    assert row.requested?
    assert_equal [ @dana, B ], [ row.requested_by, row.requested_tab ]
  end

  test "a deleted holder's row is gone from the holds" do
    ghost = User.create!(email_address: "ghost@example.com", password: "a-long-password-1")
    hold(@block, ghost, B)
    assert holds(@olga, A).any?
    ghost.destroy!
    assert_not holds(@olga, A).any?
  end

  test "it costs the same statements for 1 hold and for 20" do
    hold(@block, @dana, B)
    one = capture_sql { holds(@olga, A).of(@block) }.size

    19.times do |i|
      block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
      hold(block, users(:author), "tab-#{i.to_s.rjust(8, '0')}")
    end
    many = capture_sql { holds(@olga, A).of(@block) }.size
    assert_equal one, many
    assert_operator many, :<=, 3
    assert_equal 20, holds(@olga, A).instance_variable_get(:@rows).size
  end

  test "none answers nil to everything" do
    none = Editing::Holds.none
    assert_not none.any?
    assert_nil none.of(@block)
    assert_nil none.other(@block)
  end
end
