require "test_helper"

class Admin::Ui::SystemCheckRowComponentTest < ViewComponent::TestCase
  def result(**overrides)
    Setup::SystemCheck::Result.new(**{ label: "Site address", status: :warning, message: "No site address is set.",
      command: Setup::SystemCheck::SITE_ADDRESS_COMMAND }.merge(overrides))
  end

  test "a warning is a dot and the word Warning" do
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result))

    assert_selector "li[data-status=warning] .admin-state-chip[data-state-tone=warn]", text: "Warning"
    assert_selector "li .admin-state-chip span.bg-warn[aria-hidden=true]", visible: :all
    assert_selector "p", text: "Site address"
  end

  test "an OK row is a dot and the word OK" do
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(status: :ok, command: nil)))

    assert_selector "li[data-status=ok] .admin-state-chip[data-state-tone=ok]", text: "OK"
    assert_selector "li .admin-state-chip span.bg-ok[aria-hidden=true]", visible: :all
    assert_no_selector "code"
    assert_no_selector "button"
  end

  test "an off row is a hollow dot and the word Off, in the state chip's neutral tone" do
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(status: :off, command: nil)))

    assert_selector "li[data-status=off] .admin-state-chip[data-state-tone=off]", text: "Off"
    assert_no_selector ".admin-state-chip[data-state-tone=warn]"
  end

  test "OK and Warning are keys, drawn by the state chip" do
    assert_equal "OK", I18n.t("admin.components.ui.system_check_row.ok")
    I18n.backend.store_translations(:en, admin: { components: { ui: { system_check_row: { ok: "Fine", warning: "Careful" } } } })
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(status: :ok, command: nil)))
    assert_selector ".admin-state-chip[data-state-tone=ok]", text: "Fine"

    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result))
    assert_selector ".admin-state-chip[data-state-tone=warn]", text: "Careful"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { ui: { system_check_row: { ok: "OK", warning: "Warning" } } } })
  end

  test "the command's Copy is the copy box, named for its check, and Learn more is a key" do
    command = %(echo "<b>&" 'x')
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 2, result: result(command: command, docs: "https://example.org/site")))

    assert_selector "li div[data-controller='admin--ui--clipboard'] code#check-command-2[data-admin--ui--clipboard-target=source]", exact_text: command
    assert_no_selector "code b"
    assert_no_selector "[data-admin--ui--clipboard-text-value]"
    assert_selector "button[aria-label='Copy command for Site address'][data-action='click->admin--ui--clipboard#copy']", exact_text: "Copy"
    assert_selector "[data-admin--ui--clipboard-target=status][aria-live=polite]", visible: :all
    assert_equal "Copy command for Site address", I18n.t("admin.components.ui.system_check_row.copy_label", label: "Site address")

    link = page.find("a[href='https://example.org/site']", exact_text: "Learn more →")
    assert_includes link[:class], Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)
    I18n.backend.store_translations(:en, admin: { components: { ui: { system_check_row: { learn_more: "Read on" } } } })
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(docs: "https://example.org/site")))
    assert_selector "a[href='https://example.org/site']", exact_text: "Read on"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { ui: { system_check_row: { learn_more: "Learn more →" } } } })
  end

  test "not copyable (the setup wizard): the command is the copy box's value alone, with no Copy button or controller" do
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result, copyable: false))

    assert_selector "code#check-command-0.font-cs-mono.whitespace-nowrap", exact_text: Setup::SystemCheck::SITE_ADDRESS_COMMAND
    assert_no_selector "button"
    assert_no_selector "[data-controller]"
    assert_no_selector "[data-admin--ui--clipboard-target]"
  end

  test "the index is required, so no two rows share a command's id" do
    assert_raises(ArgumentError) { Admin::Ui::SystemCheckRowComponent.new(result: result) }
  end

  test "a docs link shows only when there is one" do
    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(docs: "https://example.org/mail")))
    assert_selector "a[href='https://example.org/mail']"

    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result))
    assert_no_selector "a"
  end

  test "a Mail row links to Settings at the address the screen hands over, and only then" do
    mail = result(label: "Mail", command: nil, link: :mail_settings)

    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: mail, mail_settings_href: "/cs-studio/settings#mail"))
    link = page.find("a[href='/cs-studio/settings#mail']", text: "Open Mail settings →")
    assert_includes link[:class], Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)

    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: mail))
    assert_no_selector "a"

    render_inline(Admin::Ui::SystemCheckRowComponent.new(index: 0, result: result(command: nil), mail_settings_href: "/cs-studio/settings#mail"))
    assert_no_selector "a"
  end
end
