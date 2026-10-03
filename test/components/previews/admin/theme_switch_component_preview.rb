class Admin::ThemeSwitchComponentPreview < ViewComponent::Preview
  def default = render(Admin::ThemeSwitchComponent.new)
end
