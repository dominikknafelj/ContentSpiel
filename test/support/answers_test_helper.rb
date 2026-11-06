# What the responders' tests share (`test/controllers/admin/answers/`): a
# context drawn with the test's own view, and an answer read back as the
# browser reads it, one `[action, target]` pair per stream in the order they
# are applied.
module AnswersTestHelper
  def answers_context(page, holds: Editing::Holds.none, viewer: users(:one))
    Admin::Answers::Context.new(view: view, page: page, locale: :en, url_options: {}, holds: holds, viewer: viewer)
  end

  # The top-level `<turbo-stream>` elements only: a stream's template may hold
  # markup of its own, never another stream.
  def streams_of(answer)
    stream_nodes(answer).map { |node| [ node["action"], node["target"] ] }
  end

  def stream_nodes(answer)
    Nokogiri::HTML5.fragment(answer.streams.join).element_children.select { |node| node.name == "turbo-stream" }
  end

  def chip = Admin::EditorScreen::PublishingStateComponent::PARTS.fetch(:chip)

  def section_counts(section)
    card = Admin::EditorScreen::SectionCardComponent
    [ [ "replace", card.summary_id(section) ], [ "replace", card.delete_count_id(section) ] ]
  end

  def dom_id_of(record) = ActionView::RecordIdentifier.dom_id(record)
end
