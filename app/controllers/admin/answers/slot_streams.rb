module Admin
  module Answers
    # A stream slot's entries (`Admin::Slots`, the stream shape), as streams
    # for a write's answer: each entry that renders replaces the element its
    # `stream_target` names with itself. With nothing registered there is no
    # stream. The answer that names the slot draws what features registered
    # after its own write and never learns what they are.
    #
    # The context is a stream's, smaller than the page's: no `query:` and no
    # `reads:`, so an entry reads what it draws itself.
    module SlotStreams
      def self.for(slot, record, view:, viewer:, **context)
        builder = Answers.stream_builder(view)
        Admin::Slots.entries(slot).filter_map do |entry|
          component = entry.component.new(record:, viewer:, data: nil, **context, **entry.options)
          builder.replace(component.stream_target, component) if component.render?
        end
      end
    end
  end
end
