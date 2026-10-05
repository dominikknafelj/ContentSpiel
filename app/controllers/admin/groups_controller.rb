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
      # One grouped query each, however many groups: never a count per row.
      @member_counts = AccessControl::Membership.group(:group_id).count
      @token_counts = ApiToken.active.group(:group_id).count
    end

    def new
      @group = AccessControl::Group.new
      @grants = []
      load_editor
    end

    def create
      save(AccessControl::Group.new, :new)
    end

    def edit
      @stale = AccessControl::LiveGrants.new(@group.grants.to_a)
      # What the editor shows -- and so submits: the live values plus a removed
      # content type, carried until Remove (`LiveGrants::Entry#carried_attributes`).
      @grants = @stale.carried_attributes
      load_editor
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
          @stale = AccessControl::LiveGrants.new(@group.grants.to_a) if @group.persisted?
          @open_keys = open_keys_from(result)
          @member_ids = attributes[:member_ids].map(&:to_i)
          load_editor
          render template, status: :unprocessable_entity
        end
      end
    end

    # What the editor screens share (round 3 Task 11):
    #
    # - `@view_only`: a stored group the viewer can't manage as it stands
    #   (`AccessControl.can_manage_group?`: every grant it stores is one they could hand
    #   out themselves, a removed content type's name included) is read-only -- the
    #   whole form disabled, no footer, no delete zone.
    #   `Groups::Save`/`Groups::Destroy` ask the same question again and are the
    #   backstop for a forged request; this decides only what is drawn. A new group
    #   has nothing stored to be unable to manage.
    # - `@members`: the member chips, in one query (the posted list after a failed save).
    # - the delete zone's numbers: one count and one preloaded list of the ACTIVE tokens.
    def load_editor
      @view_only = @group.persisted? && !AccessControl.can_manage_group?(Current.actor, @group)
      ids = @member_ids || (@group.persisted? ? @group.memberships.pluck(:user_id) : [])
      @members = User.where(id: ids).order(:email_address).to_a
      # What the group stores, as the editor carries it: the matrix locks a row only while it still is this.
      @stored_grants = @group.persisted? ? AccessControl::LiveGrants.new(@group.grants.to_a).carried_attributes : []
      return unless @group.persisted? && !@view_only

      @member_count = @group.memberships.count
      @tokens = @group.api_tokens.active.includes(:user).order(:id).to_a
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
        # A removed type is carried by the editor (`ScopeEditorComponent`) but
        # means nothing on its own: with no live type ticked the editor says "all
        # content types", so a scope of only carried ones would instead match
        # nothing. Read that as the editor shows it.
        scope["content_types"] = types if permission.scopes.include?(:content_type) && (types & AccessControl::Permissions.content_type_choices).any?
        scope["own"] = true if permission.scopes.include?(:own) && values["own"] == "1"
        page_ids = Array(values["page_ids"]).compact_blank
        scope["page_ids"] = page_ids.map { |id| AccessControl::LiveGrants.integer_or_self(id) } if permission.scopes.include?(:branch) && page_ids.any?
        { permission: permission.key, scope: scope }
      end
    end

    # After a refusal, the rows whose editor should start open: the ones an
    # error names ("posts.edit: ..."), so the editor sees what was refused.
    def open_keys_from(result)
      result.record.errors.full_messages.filter_map { |message| message[/\A([a-z0-9_\/]+\.[a-z0-9_]+):/, 1] }
    end
  end
end
