require "test_helper"

# The visitor (`AccessControl::VISITOR`) may send a
# form, which no group, token or user may be given. What keeps that right
# from leaking is who may ACT as the visitor: in the application, the one
# controller that takes a visitor's send (`FormSendsController`) and nothing
# else, so no other door of the site can authorize a
# write as somebody nobody signed in as. The visitor's other guard is
# test/models/access_control/visitor_test.rb (every key on every channel).
#
# A source grep, comments stripped: it does not see the constant reached
# another way (`const_get`, a variable handed in), and it reads a test's
# name of the constant only to keep the tests that act as a visitor to the
# ones about the visitor.
class VisitorActorTest < ActiveSupport::TestCase
  VISITOR = /\bAccessControl::VISITOR\b|(?<![:\w])VISITOR\b/

  # Where the constant is defined, not used.
  DEFINITION = "app/models/access_control.rb"

  APP_NAMERS = %w[app/controllers/form_sends_controller.rb].freeze

  TEST_NAMERS = %w[
    test/lib/visitor_actor_test.rb
    test/models/access_control/visitor_test.rb
    test/services/forms/submit_test.rb
  ].freeze

  def namers(*roots)
    roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,erb}") }.filter_map do |path|
      code = path.read.lines.reject { |line| line.strip.start_with?("#", "<%#") }.join
      path.to_s.delete_prefix("#{Rails.root}/") if code.match?(VISITOR)
    end.sort
  end

  test "only FormSendsController and Forms::Submit's tests name AccessControl::VISITOR" do
    app = namers("app", "lib") - [ DEFINITION ]
    assert_empty app - APP_NAMERS, "only the endpoint that takes a visitor's send acts as the visitor"

    tests = namers("test")
    assert_empty tests - TEST_NAMERS, "a test that acts as the visitor is about the visitor or the send"
  end

  # A second visitor would be a second way to act as one: `Visitor.new` and
  # `Visitor[]` are private, and nothing outside the class's own file
  # writes either (or `allocate`), in the application or in a test.
  CONSTRUCTION = /\bVisitor\s*(?:\.\s*(?:new|allocate|send|public_send|__send__)\b|\[)/
  CLASS_FILE = "app/models/access_control/visitor.rb"

  test "the visitor is one instance: nothing else constructs one, and new and [] are private" do
    constructors = %w[app lib test].flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,erb}") }.filter_map do |path|
      relative = path.to_s.delete_prefix("#{Rails.root}/")
      next if [ CLASS_FILE, "test/lib/visitor_actor_test.rb" ].include?(relative)

      code = path.read.lines.reject { |line| line.strip.start_with?("#", "<%#") }.join
      relative if code.match?(CONSTRUCTION)
    end
    assert_empty constructors, "only #{CLASS_FILE} makes the visitor"

    assert_raises(NoMethodError) { AccessControl::Visitor.new }
    assert_raises(NoMethodError) { AccessControl::Visitor[] }
    assert_same AccessControl::VISITOR, AccessControl::Visitor::ONE
  end

  test "a copy of the visitor is no visitor" do
    copy = AccessControl::VISITOR.dup
    assert_kind_of AccessControl::Visitor, copy
    assert_not AccessControl.allowed?(copy, "forms.submit", forms(:contact), channel: :public)
    assert AccessControl.allowed?(AccessControl::VISITOR, "forms.submit", forms(:contact), channel: :public)

    # The audit log asks for the instance too (`Visitor.one?`): a copy is
    # not written as the visitor, nor as anybody.
    assert_not AccessControl::Visitor.one?(copy)
    assert_raises(ArgumentError) { Current.set(actor: copy, channel: :public) { Audit.record("form_submission.received", subject: forms(:contact)) } }
    event = Current.set(actor: AccessControl::VISITOR, channel: :public) { Audit.record("form_submission.received", subject: forms(:contact), coalesce: false) }
    assert_equal [ nil, Audit::VISITOR_LABEL ], [ event.actor, event.actor_label ]
  end

  test "the definition is where the guard looks for it" do
    assert_includes namers("app"), DEFINITION
  end
end
