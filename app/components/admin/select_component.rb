module Admin
  # A styled native `<select>` (design pass spec §4): `.cs-select` supplies
  # the border, token-coloured chevron and focus ring. `options` is anything
  # `options_for_select` accepts. Existing `select_tag` calls elsewhere just
  # take `setup_select_class`; this component is for new code that wants the
  # whole control as one unit.
  class SelectComponent < AdminComponent
    def initialize(name:, options:, selected: nil, id: nil, include_blank: nil, **html)
      @name = name
      @options = options
      @selected = selected
      @id = id
      @include_blank = include_blank
      @html = html
    end

    def call
      select_tag(@name, options_for_select(@options, @selected), id: @id, include_blank: @include_blank,
        class: [ "cs-select", @html[:class] ], **@html.except(:class))
    end
  end
end
