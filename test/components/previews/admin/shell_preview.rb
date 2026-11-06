class Admin::ShellPreview < ViewComponent::Preview
  def sidebar
    render(Admin::Shell::SidebarComponent.new(modules: StudioModules.entries.map(&:to_row), user: User.first || User.new(email_address: "ada@example.com", owner: true),
      current_path: "/cs-studio/posts", url_options: {}, badges: { trash: 3, dashboard: 2 }))
  end

  def top_bar = render(Admin::Shell::TopBarComponent.new)

  def top_bar_with_tree = render(Admin::Shell::TopBarComponent.new(tree: true))

  def command_palette = render(Admin::Shell::CommandPaletteComponent.new)
end
