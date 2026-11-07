# A panel registered at `editor.rail.tabs` in a test: answers the panel shape
# (`tab_key`, `tab_label`, `tab_count`, `render?`) and draws what it was handed.
class RailTabProbe < ViewComponent::Base
  def initialize(record:, viewer:, data: nil, **context)
    @record = record
    @context = context
  end

  def tab_key = "probe"
  def tab_label = "Probe"
  def tab_count = 3
  def render? = true

  def call = tag.p("#{@record.id} #{@context.sort.to_h.inspect}", data: { probe: true })

  class Quiet < RailTabProbe
    def tab_key = "quiet"
    def render? = false
  end
end
