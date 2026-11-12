require "ripper"

# THE SHARED CONTRACT TEST's checks. A shared CS Studio component declares
# its contract (`Admin::Ui::Contract`, app/components/admin/ui/contract.rb),
# and `assert_contract` holds the declaration to the code: the keywords of
# `initialize`, the ViewComponent slots, the keys it owns in ui.en.yml, its
# controller's file and that the component attaches it itself, and the browser
# tests its script-held states and its keyboard name (or the sentence that it
# takes no focus). The components are
# derived from the files, so a new one is in every check from the day its
# file is written.
#
# What it cannot read is said in the declaration and checked by a person: the
# accessibility sentence, the motion, the content edges, the widths and the
# limits.
module UiContract
  # A new component whose keyboard browser test comes in a later task of the
  # same pull request, mapped to the reason, so no commit between the two is
  # red. Empty when a pull request is merged.
  KEYBOARD_NOT_YET = {
    "Admin::Ui::RecoveryCodesComponent" => "its keyboard test is written with the Account screen, Task 10",
    "Admin::Ui::ConfirmIdentityDialogComponent" => "its keyboard test is written with the four actions it gates on the Account screen, Task 10"
  }.freeze

  PLURAL_KEYS = %i[zero one two few many other].freeze

  # Ruby source's lexer tokens (`Ripper.lex`) outside a `contract(...)` call
  # that starts a line: the declaration names its controller and says its
  # sentences, so a check of the rest of the source, or of the source's words
  # (test/lib/admin_i18n_test.rb), reads around it.
  def self.outside_contract(source) = contract_partition(source).last

  # The text of the `contract(...)` calls that start a line: what a
  # stylesheet's scan reads of a declaration
  # (test/components/component_contract_test.rb).
  def self.contract_text(source) = contract_partition(source).first.map { |_, _, text| text }.join

  # The lexer tokens split in two: those of the `contract(...)` calls that
  # start a line, and the rest.
  def self.contract_partition(source)
    lines = source.lines
    # The parentheses still open in a `contract(` call, while inside one.
    depth = nil
    Ripper.lex(source).partition do |(line, _column), type, text|
      if depth.nil? && type == :on_ident && text == "contract" && lines[line - 1].to_s.strip.start_with?("contract(")
        depth = 0
        next true
      end
      next false if depth.nil?

      depth += 1 if type == :on_lparen
      depth -= 1 if type == :on_rparen
      depth = nil if depth.zero? && type == :on_rparen
      true
    end
  end

  # Whether `source` attaches `identifier` itself: in a `data-controller`
  # attribute's list, or in the list of a `controller:` key of a tag's
  # `data:` (the media picker's dialog attaches two). A target or an action
  # of it (`data-<identifier>-target`, `click->identifier#act`) is not an
  # attachment.
  def self.attaches?(source, identifier)
    name = /(?<![\w-])#{Regexp.escape(identifier)}(?![\w-])/
    lists = source.scan(/data-controller=["']([^"']*)["']/) + source.scan(/controller:\s*["']([^"']*)["']/)
    lists.flatten.any? { |list| list.match?(name) }
  end

  # What the controller check reads of a component: its templates whole, and
  # its Ruby without comments and without the declaration.
  def self.own_source(klass)
    ruby = Object.const_source_location(klass.name)&.first or return ""
    ruby_text = outside_contract(File.read(ruby)).reject { |_, type, _| %i[on_comment on_embdoc on_embdoc_beg on_embdoc_end].include?(type) }.map { |_, _, text| text }.join
    templates = Dir["#{ruby.delete_suffix('.rb')}.*"].reject { |path| path == ruby }.map { |path| File.read(path) }
    [ ruby_text, *templates ].join("\n")
  end

  # What may take the focus in a component's own markup, from HTML's
  # focusable set: a link or an image map's area with an address, a form
  # control (a tag, a `*_tag` helper, any `*_field_tag`, or a form builder,
  # whose fields are controls), a summary, a frame or an embedded object, an
  # audio or video with its controls, a dialog, a tabindex or
  # contenteditable.
  FOCUSABLE = {
    "a link" => /<(?:a|area)\b[^>]*\bhref|\b(?:link_to|link_to_if|link_to_unless|mail_to|phone_to|sms_to)\b|\btag\.(?:a|area)\b|content_tag[( ]\s*:(?:a|area)\b/,
    "a control" => /<(?:button|input|select|textarea)\b|\b\w+_field_tag\b|\b(?:button_to|button_tag|submit_tag|image_submit_tag|check_box_tag|radio_button_tag|text_area_tag|select_tag)\b|\btag\.(?:button|input|select|textarea)\b|content_tag[( ]\s*:(?:button|input|select|textarea)\b/,
    "a form" => /\b(?:form_with|form_for|form_tag|fields_for)\b\s*[(\s]|<form\b|\btag\.form\b/,
    "a summary" => /<summary\b|\btag\.summary\b|content_tag[( ]\s*:summary\b/,
    "a frame" => /<(?:iframe|embed|object)\b|\btag\.(?:iframe|embed|object)\b|content_tag[( ]\s*:(?:iframe|embed|object)\b/,
    "a media control" => /<(?:audio|video)\b[^>]*\bcontrols|\btag\.(?:audio|video)\b[^\n]*\bcontrols/,
    "a dialog" => /<dialog\b|\btag\.dialog\b|content_tag[( ]\s*:dialog\b/,
    "a tabindex" => /\btabindex\b/i,
    "contenteditable" => /\bcontenteditable\b/i
  }.freeze

  # A component's own source with ERB comments taken out, as the focus check
  # reads it (`own_source` keeps a template whole).
  def self.markup_source(klass) = own_source(klass).gsub(/<%#.*?%>/m, "")

  # The `Admin::Ui` components a source renders by name.
  def self.rendered_components(klass)
    markup_source(klass).scan(/(?:Admin::Ui::)?\b([A-Z]\w*Component)\.new\b/).flatten.uniq
      .filter_map { |name| "Admin::Ui::#{name}".safe_constantize }.reject { |other| other == klass }
  end

  # What a component that says it takes no focus draws that can take it, as
  # sentences: its own markup, the markup of each `Admin::Ui` component it
  # renders by name (followed through their own renders) and of each partial
  # it renders by path. What it cannot read is answered apart, in
  # `unreadable_parts`.
  def self.focusable_parts(klass, seen = Set.new)
    return [] unless seen.add?(klass)

    source = markup_source(klass)
    own = FOCUSABLE.filter_map { |what, pattern| "#{klass.name} draws #{what}" if source.match?(pattern) }
    partials = source.scan(/render[( ]\s*["']([\w\/]+)["']/).flatten.filter_map do |path|
      file = Rails.root.join("app/views", File.dirname(path), "_#{File.basename(path)}.html.erb")
      text = file.exist? ? file.read.gsub(/<%#.*?%>/m, "") : ""
      FOCUSABLE.filter_map { |what, pattern| "#{klass.name}'s partial #{path} draws #{what}" if text.match?(pattern) }
    end.flatten
    own + partials + rendered_components(klass).flat_map { |other| focusable_parts(other, seen) }
  end

  # What a check of a component's own markup cannot see: its slots and the
  # block it is handed, which a caller fills, and a render of something that
  # is not named in the source (a registered entry's component, a panel
  # handed over). A component it renders by name passes up its own such
  # renders; its slots and its block are filled by the component that
  # renders it, in a source this check reads.
  def self.unreadable_parts(klass, seen = Set.new)
    return [] unless seen.add?(klass)

    source = markup_source(klass)
    dynamic = source.scan(/render[( ]\s*([^\s"'()]+)/).flatten.reject { |target| target.match?(/\A(?:Admin::Ui::)?[A-Z]\w*Component\.new\b/) }
    block = source.match?(/(?<![\w.:"'-])content(?![\w?:"'-])/) ? [ "the block it is handed (content)" ] : []
    passed_up = rendered_components(klass).flat_map do |other|
      unreadable_parts(other, seen).select { |part| part.include?("a render of ") }.map { |part| part.start_with?("Admin::") ? part : "#{other.name}'s #{part}" }
    end
    [ *klass.registered_slots.keys.map { |slot| "the slot #{slot}" }, *dynamic.map { |target| "a render of #{target}" }, *block, *passed_up ]
  end

  def ui_components
    Dir[Rails.root.join("app/components/admin/ui/*_component.rb")].sort.map do |file|
      "Admin::Ui::#{File.basename(file, '.rb').camelize}".constantize
    end
  end

  # `source:` is the text the controller check reads; `own_source` when nil.
  def assert_contract(klass, source: nil)
    assert_operator klass, :include?, Admin::Ui::Contract, "#{klass.name} does not include Admin::Ui::Contract"
    assert_not_nil klass.contract, "#{klass.name} does not declare its contract"

    assert_contract_interface(klass)
    assert_contract_slots(klass)
    assert_contract_keys(klass)
    assert_contract_controller(klass, source: source)
    assert_contract_script_states(klass)
    assert_contract_keyboard(klass)
  end

  # The declaration, after asserting there is one, so a check run on a class
  # that has not declared says which class.
  def declared_contract(klass)
    assert klass.respond_to?(:contract), "#{klass.name} does not include Admin::Ui::Contract"
    klass.contract.tap { |contract| assert_not_nil contract, "#{klass.name} does not declare its contract" }
  end

  def assert_contract_interface(klass)
    keywords = klass.instance_method(:initialize).parameters.filter_map { |kind, name| name if %i[key keyreq].include?(kind) }
    assert_equal keywords.sort, declared_contract(klass).interface.sort,
      "#{klass.name}'s contract interface is not its keywords: #{keywords.sort.inspect}"
  end

  def assert_contract_slots(klass)
    slots = klass.registered_slots.keys
    assert_equal slots.sort, declared_contract(klass).slots.sort, "#{klass.name}'s contract slots are not its slots: #{slots.sort.inspect}"
  end

  # The leaves under `admin.components.ui.<name>`, a Hash of plural
  # categories alone being one leaf.
  def assert_contract_keys(klass)
    scope = "admin.components.ui.#{klass.name.demodulize.delete_suffix('Component').underscore}"
    owned = contract_leaves(I18n.t(scope, locale: :en, default: {}))
    declared = declared_contract(klass).keys
    assert_empty declared - owned, "#{klass.name}'s contract keys name #{(declared - owned).join(', ')}, missing under #{scope}"
    assert_empty owned - declared, "#{klass.name} owns #{(owned - declared).join(', ')} under #{scope}, and its contract keys leave them out"
  end

  def assert_contract_controller(klass, source: nil)
    identifier = declared_contract(klass).controller
    return if identifier.nil?

    file = Rails.root.join("app/javascript/controllers/#{identifier.gsub('--', '/').tr('-', '_')}_controller.js")
    assert File.exist?(file), "#{klass.name}'s contract controller #{identifier} has no file: #{file.relative_path_from(Rails.root)}"
    source ||= UiContract.own_source(klass)
    assert UiContract.attaches?(source, identifier),
      "#{klass.name}'s contract controller #{identifier} is not attached in its own markup (a data-controller or a controller: key), outside its declaration and its comments"
  end

  # A state in both `states:` and `script_states:` is refused by the
  # declaration itself (`Admin::Ui::Contract`), when the class loads.
  def assert_contract_script_states(klass)
    declared_contract(klass).script_states.each do |state, (file, name)|
      assert_browser_test(file, name, "#{klass.name}'s contract script_states #{state}")
    end
  end

  # A sentence (a component that takes no focus) names no test to look for,
  # and is allowed only to a component whose own markup draws nothing that can
  # take the focus. A slot is filled by its caller, out of this check's
  # sight: a component with one may say it takes no focus only by naming the
  # slot in its sentence (the person who reads it checks the callers), and a
  # block it is handed, or a render of something not named in the source (a
  # registered entry, a panel handed over), is refused outright, since what
  # it draws could take the focus.
  def assert_contract_keyboard(klass)
    keyboard = declared_contract(klass).keyboard
    return assert_browser_test(*keyboard, "#{klass.name}'s contract keyboard") if keyboard.is_a?(Array)
    return unless keyboard.is_a?(String)

    drawn = UiContract.focusable_parts(klass)
    assert_empty drawn, "#{klass.name} says it takes no focus, but it draws what can take it: name its keyboard browser test instead"
    unreadable = UiContract.unreadable_parts(klass)
    unnamed = unreadable.reject { |part| part.start_with?("the slot ") && keyboard.match?(/\b#{Regexp.escape(part.delete_prefix("the slot "))}\b/) }
    assert_empty unnamed, "#{klass.name} says it takes no focus, but this check cannot read #{unnamed.join(', ')}: " \
      "name a slot in the sentence, or name its keyboard browser test"
  end

  private

  def assert_browser_test(file, name, what)
    path = Rails.root.join(file)
    assert File.exist?(path), "#{what} names #{file}, which is not there"
    assert_includes File.read(path), %(test "#{name}"), "#{what} names the test \"#{name}\", which #{file} does not hold"
  end

  def contract_leaves(tree, prefix = nil)
    return [ prefix ].compact unless tree.is_a?(Hash)
    return [ prefix ] if prefix && tree.keys.all? { |key| PLURAL_KEYS.include?(key.to_sym) }

    tree.flat_map { |key, value| contract_leaves(value, [ prefix, key ].compact.join(".")) }
  end
end
