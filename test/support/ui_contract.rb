# THE SHARED CONTRACT TEST's checks. A shared CS Studio component declares
# its contract (`Admin::Ui::Contract`, app/components/admin/ui/contract.rb),
# and `assert_contract` holds the declaration to the code: the keywords of
# `initialize`, the ViewComponent slots, the keys it owns in ui.en.yml, its
# controller's file and its name in the component's source, and the browser
# tests its script-held states and its keyboard name. The components are
# derived from the files, so a new one is in every check from the day its
# file is written.
#
# What it cannot read is said in the declaration and checked by a person: the
# accessibility sentence, the motion, the content edges, the widths and the
# limits.
module UiContract
  # The 43 components of app/components/admin/ui when the contract came. A
  # component on it may declare `keyboard: nil`; one made after it names its
  # keyboard browser test. Frozen: it only shrinks, when a component on it
  # gains its keyboard test or is deleted, and nothing is ever added.
  MADE_BEFORE_CONTRACT = %w[
    Admin::Ui::AvatarComponent Admin::Ui::BadgeComponent Admin::Ui::ButtonComponent
    Admin::Ui::ChannelChipComponent Admin::Ui::CheckboxComponent Admin::Ui::ChipInputComponent
    Admin::Ui::ConfirmDialogComponent Admin::Ui::ContentTypeDotComponent Admin::Ui::DialogComponent
    Admin::Ui::EmptyStateComponent Admin::Ui::ErrorSummaryComponent Admin::Ui::FieldComponent
    Admin::Ui::FileDropComponent Admin::Ui::IconChipComponent Admin::Ui::InsecureNoticeComponent
    Admin::Ui::LanguageTabsComponent Admin::Ui::LibraryImageComponent Admin::Ui::ListStateComponent
    Admin::Ui::MailFailedNoticeComponent Admin::Ui::MenuComponent Admin::Ui::PaginationComponent
    Admin::Ui::PasswordFieldComponent Admin::Ui::PrefixInputComponent Admin::Ui::RailPanelComponent
    Admin::Ui::RailSlotComponent Admin::Ui::RailTabComponent Admin::Ui::RailTabsComponent
    Admin::Ui::SaveBarComponent Admin::Ui::SaveStatusComponent Admin::Ui::ScheduledDateComponent
    Admin::Ui::SlotComponent Admin::Ui::StatusChipComponent Admin::Ui::SystemCheckRowComponent
    Admin::Ui::TabLinksComponent Admin::Ui::ThemeSwitchComponent Admin::Ui::TimeAgoComponent
    Admin::Ui::ToastComponent Admin::Ui::ToastRegionComponent Admin::Ui::TooltipComponent
    Admin::Ui::TranslationChipComponent Admin::Ui::UnpublishedChipComponent Admin::Ui::UserNameComponent
    Admin::Ui::WordDiffComponent
  ].freeze

  # A new component whose keyboard browser test comes in a later task of the
  # same pull request, mapped to the reason, so no commit between the two is
  # red. Empty when a pull request is merged.
  KEYBOARD_NOT_YET = {}.freeze

  # The components that do not declare their contract yet: every one but the
  # first five declared. It goes when the last of them declares.
  UNDECLARED = (MADE_BEFORE_CONTRACT - %w[
    Admin::Ui::ButtonComponent Admin::Ui::StatusChipComponent Admin::Ui::DialogComponent
    Admin::Ui::ListStateComponent Admin::Ui::SlotComponent
  ]).freeze

  PLURAL_KEYS = %i[zero one two few many other].freeze

  def ui_components
    Dir[Rails.root.join("app/components/admin/ui/*_component.rb")].sort.map do |file|
      "Admin::Ui::#{File.basename(file, '.rb').camelize}".constantize
    end
  end

  # `source:` is the text the controller check reads; the component's own
  # `.rb` and templates when nil.
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

  def assert_contract_interface(klass)
    keywords = klass.instance_method(:initialize).parameters.filter_map { |kind, name| name if %i[key keyreq].include?(kind) }
    assert_equal keywords.sort, klass.contract.interface.sort,
      "#{klass.name}'s contract interface is not its keywords: #{keywords.sort.inspect}"
  end

  def assert_contract_slots(klass)
    slots = klass.registered_slots.keys
    assert_equal slots.sort, klass.contract.slots.sort, "#{klass.name}'s contract slots are not its slots: #{slots.sort.inspect}"
  end

  # The leaves under `admin.components.ui.<name>`, a Hash of plural
  # categories alone being one leaf.
  def assert_contract_keys(klass)
    scope = "admin.components.ui.#{klass.name.demodulize.delete_suffix('Component').underscore}"
    owned = contract_leaves(I18n.t(scope, locale: :en, default: {}))
    declared = klass.contract.keys
    assert_empty declared - owned, "#{klass.name}'s contract keys name #{(declared - owned).join(', ')}, missing under #{scope}"
    assert_empty owned - declared, "#{klass.name} owns #{(owned - declared).join(', ')} under #{scope}, and its contract keys leave them out"
  end

  def assert_contract_controller(klass, source: nil)
    identifier = klass.contract.controller
    return if identifier.nil?

    file = Rails.root.join("app/javascript/controllers/#{identifier.gsub('--', '/').tr('-', '_')}_controller.js")
    assert File.exist?(file), "#{klass.name}'s contract controller #{identifier} has no file: #{file.relative_path_from(Rails.root)}"
    source ||= Dir[Rails.root.join("app/components/#{klass.name.underscore}.{rb,html.erb}")].map { |path| File.read(path) }.join("\n")
    assert_includes source, identifier, "#{klass.name}'s contract controller #{identifier} is not named in its own source"
  end

  def assert_contract_script_states(klass)
    contract = klass.contract
    both = contract.states & contract.script_states.keys
    assert_empty both, "#{klass.name}'s contract names #{both.join(', ')} in both states and script_states"
    contract.script_states.each do |state, (file, name)|
      assert_browser_test(file, name, "#{klass.name}'s contract script_states #{state}")
    end
  end

  def assert_contract_keyboard(klass)
    file, name = klass.contract.keyboard
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
