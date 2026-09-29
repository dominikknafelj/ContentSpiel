module Admin
  # The Groups module (access-control design spec §5): the list with member
  # counts, the editor (name, description, members, the permission matrix
  # -- `Admin::PermissionMatrixComponent`), and delete behind the confirm
  # dialog, which names the tokens `Groups::Destroy` will revoke.
  #
  # `groups.manage` opens the module; `Groups::Save`/`Groups::Destroy`
  # decide every write again, including the no-escalation rules for
  # non-owners (Review Focus 1) -- a refusal there is the 403 page with the
  # service's reason. A deliberate "Save group" submit rather than autosave,
  # like the Users module: a half-ticked permission matrix must never be
  # saved on its own.
  class GroupsController < BaseController
    before_action -> { require_permission("groups.manage") }
    before_action :set_group, only: %i[edit update destroy]

    def index
      @groups = AccessControl::Group.order(:name)
      @member_counts = AccessControl::Membership.group(:group_id).count
    end

    def new
      @group = AccessControl::Group.new
      @grants = []
    end

    def create
      save(AccessControl::Group.new, :new)
    end

    def edit
      @stale = AccessControl::LiveGrants.new(@group.grants.to_a)
      @grants = @stale.attributes
    end

    def update
      save(@group, :edit)
    end

    def destroy
      result = Groups::Destroy.call(@group)

      if result.ok?
        redirect_to admin_groups_path(**admin_url_options), status: :see_other, notice: "Group deleted"
      else
        forbidden_or(result) do
          redirect_to edit_admin_group_path(@group, **admin_url_options), status: :see_other, alert: result.errors.to_sentence
        end
      end
    end

    private

    def set_group
      @group = AccessControl::Group.find(params[:id])
    end

    def save(group, template)
      attributes = group_attributes
      result = Groups::Save.call(group, attributes: attributes)

      if result.ok?
        redirect_to edit_admin_group_path(result.record, **admin_url_options), status: :see_other, notice: "Group saved"
      else
        forbidden_or(result) do
          @group = result.record
          @grants = attributes[:grants]
          @member_ids = attributes[:member_ids].map(&:to_i)
          render template, status: :unprocessable_entity
        end
      end
    end

    # The form always sends the whole member list (a blank first value
    # keeps an empty list in the params) and the whole matrix, so both are
    # always passed on -- a request without them means "none", which can
    # only ever narrow a group.
    def group_attributes
      permitted = params.fetch(:group, ActionController::Parameters.new).permit(:name, :description, member_ids: [], grants: {})
      {
        name: permitted[:name],
        description: permitted[:description],
        member_ids: Array(permitted[:member_ids]).compact_blank,
        grants: grants_from(permitted[:grants]&.to_h || {})
      }
    end

    # `Admin::PermissionMatrixComponent`'s params back into `[{ permission:,
    # scope: }]`: only ticked permissions, and for each only the scope
    # controls its permission takes; an empty control is no key at all ("no
    # restriction"). An unregistered key is passed through untouched for
    # `Groups::Save` to reject.
    def grants_from(submitted)
      submitted.filter_map do |key, values|
        values = values.is_a?(Hash) ? values : {}
        next unless values["enabled"] == "1"

        permission = AccessControl::Permissions.find(key)
        next { permission: key, scope: {} } unless permission

        scope = {}
        types = Array(values["content_types"]).compact_blank
        scope["content_types"] = types if permission.scopes.include?(:content_type) && types.any?
        scope["own"] = true if permission.scopes.include?(:own) && values["own"] == "1"
        page_ids = Array(values["page_ids"]).compact_blank
        scope["page_ids"] = page_ids.map { |id| AccessControl::LiveGrants.integer_or_self(id) } if permission.scopes.include?(:branch) && page_ids.any?
        { permission: permission.key, scope: scope }
      end
    end

    # For the editor: every user, for the members list.
    helper_method def all_users = @all_users ||= User.order(:email_address).to_a

    helper_method def selected_member_ids
      @member_ids || (@group.persisted? ? @group.memberships.pluck(:user_id) : [])
    end
  end
end
