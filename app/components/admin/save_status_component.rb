module Admin
  # The autosave status line every form-with-autosave renders one of (spec
  # §6.1) -- a Turbo Stream replaces this element wholesale by its `id` as a
  # save moves through its states, so the text for each state has to be
  # exactly the wording global constraints pins down (a save controller in a
  # later task assembles the state from the fetch response; this component
  # only ever turns a state into the one sentence it's allowed to show).
  # `idle` -- nothing has changed yet, or the record just loaded -- renders
  # an empty element rather than an empty string with visible chrome around
  # it, so the header note it sits in doesn't visibly flash on load.
  class SaveStatusComponent < AdminComponent
    STATES = %i[idle saving saved error stale offline retrying].freeze

    def initialize(id:, state: :idle, at: nil, count: 0)
      raise ArgumentError, "unknown save status state #{state.inspect}" unless STATES.include?(state)

      @id = id
      @state = state
      @at = at
      @count = count
    end

    def text
      case state
      when :idle then ""
      when :saving then "Saving…"
      when :saved then "Saved #{at&.strftime('%H:%M')}"
      when :error then "Couldn't save — #{count} problems"
      when :retrying then "Not saved — retrying"
      when :offline then "Not saved — check your connection"
      when :stale then "Changed elsewhere — reload to see the latest"
      end
    end

    private

    attr_reader :id, :state, :at, :count
  end
end
