require "ripper"

# THE SHARED CONTRACT TEST's checks. A shared CS Studio component declares
# its contract (`Admin::Ui::Contract`, app/components/admin/ui/contract.rb),
# and `assert_contract` holds the declaration to the code: the keywords of
# `initialize`, the ViewComponent slots, the keys it owns in ui.en.yml, its
# controller's file and that the component attaches it itself, and the browser
# tests its script-held states and its keyboard name. The components are
# derived from the files, so a new one is in every check from the day its
# file is written.
#
# What it cannot read is said in the declaration and checked by a person: the
# accessibility sentence, the motion, the content edges, the widths and the
# limits.
module UiContract
  # The components of app/components/admin/ui made before the contract that
  # name no keyboard browser test yet: one on it may declare `keyboard: nil`,
  # and every other component names its test. Frozen: it only shrinks, when a
  # component on it declares its keyboard test or is deleted, and nothing is
  # ever added (test/lib/component_parts_test.rb).
  MADE_BEFORE_CONTRACT = %w[
    Admin::Ui::ActorAvatarComponent Admin::Ui::AvatarComponent Admin::Ui::BadgeComponent Admin::Ui::ButtonComponent
    Admin::Ui::ChannelChipComponent Admin::Ui::CheckboxComponent
    Admin::Ui::ConfirmDialogComponent Admin::Ui::ContentTypeDotComponent Admin::Ui::DialogComponent
    Admin::Ui::EmptyStateComponent Admin::Ui::ErrorSummaryComponent Admin::Ui::FieldComponent
    Admin::Ui::FileDropComponent Admin::Ui::IconChipComponent Admin::Ui::InsecureNoticeComponent
    Admin::Ui::LanguageTabsComponent Admin::Ui::LibraryImageComponent Admin::Ui::ListStateComponent
    Admin::Ui::MailFailedNoticeComponent Admin::Ui::PaginationComponent
    Admin::Ui::PasswordFieldComponent Admin::Ui::PrefixInputComponent Admin::Ui::RailPanelComponent
    Admin::Ui::RailSlotComponent Admin::Ui::RailTabComponent
    Admin::Ui::SaveBarComponent Admin::Ui::SaveStatusComponent Admin::Ui::ScheduledDateComponent
    Admin::Ui::SlotComponent Admin::Ui::StatusChipComponent Admin::Ui::SystemCheckRowComponent
    Admin::Ui::TabLinksComponent Admin::Ui::ThemeSwitchComponent Admin::Ui::TimeAgoComponent
    Admin::Ui::ToastComponent Admin::Ui::ToastRegionComponent
    Admin::Ui::TranslationChipComponent Admin::Ui::UnpublishedChipComponent Admin::Ui::UserNameComponent
    Admin::Ui::WordDiffComponent
  ].freeze

  # A new component whose keyboard browser test comes in a later task of the
  # same pull request, mapped to the reason, so no commit between the two is
  # red. Empty when a pull request is merged.
  KEYBOARD_NOT_YET = {}.freeze

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
  # attribute's list, or as the value of a `controller:` key of a tag's
  # `data:`. A target or an action of it (`data-<identifier>-target`,
  # `click->identifier#act`) is not an attachment.
  def self.attaches?(source, identifier)
    name = /(?<![\w-])#{Regexp.escape(identifier)}(?![\w-])/
    source.scan(/data-controller=["']([^"']*)["']/).flatten.any? { |list| list.match?(name) } ||
      source.match?(/controller:\s*["']#{Regexp.escape(identifier)}["']/)
  end

  # What the controller check reads of a component: its templates whole, and
  # its Ruby without comments and without the declaration.
  def self.own_source(klass)
    ruby = Object.const_source_location(klass.name)&.first or return ""
    ruby_text = outside_contract(File.read(ruby)).reject { |_, type, _| %i[on_comment on_embdoc on_embdoc_beg on_embdoc_end].include?(type) }.map { |_, _, text| text }.join
    templates = Dir["#{ruby.delete_suffix('.rb')}.*"].reject { |path| path == ruby }.map { |path| File.read(path) }
    [ ruby_text, *templates ].join("\n")
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

  def assert_contract_keyboard(klass)
    file, name = declared_contract(klass).keyboard
    assert_browser_test(file, name, "#{klass.name}'s contract keyboard") if file
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
