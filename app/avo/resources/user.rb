class Avo::Resources::User < Avo::BaseResource
  self.icon = "tabler/outline/users"
  # self.avatar = {
  #   source: :avatar
  # }
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    # field :avatar, as: :avatar
    field :email_address, as: :text
    # `has_secure_password` requires a password on create, so without these the
    # New form could never be submitted successfully.
    field :password, as: :password
    field :password_confirmation, as: :password
  end

  # Users are the only way into this app's admin, so deleting the last one would
  # lock everyone out -- the only other way to create a User is the
  # development-only seed. Avo 4.2.3 Community has no `destroy_enabled` flag
  # (per-action gating lives in the avo-authorization plugin, which isn't
  # installed and stubs out to "always allowed"), so the Delete button is
  # dropped from the controls here and Avo::UsersController turns the DELETE
  # route away. Both halves are needed: hiding the button alone leaves the route.
  def render_show_controls
    without_delete_button(super)
  end

  def render_edit_controls
    without_delete_button(super)
  end

  def render_row_controls(item:)
    without_delete_button(super)
  end

  private

  def without_delete_button(controls)
    controls.reject { |control| control.is_a?(Avo::Resources::Controls::DeleteButton) }
  end
end
