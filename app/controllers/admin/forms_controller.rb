module Admin
  # The Forms screen (forms plan, Task 4; design.md 1 and 2): the list of
  # kept forms, New form (a dialog on the list, `new` its page without
  # JavaScript), the builder (`show`), its explicit Save (`update`) and Move
  # to trash (`destroy`). Every write is a service: `Forms::Save` and
  # `Trash::Move`; this controller turns what the builder posted into their
  # arguments (`Admin::FormsScreen::Draft`) and their answers into a
  # redirect or the screen drawn again.
  #
  # WHO OPENS IT. The list opens for a holder of either right, `forms.manage`
  # or `form_submissions.view` (the rights are site-wide, as the library's
  # is: a 403 without both); everything that builds or changes a form needs
  # `forms.manage`. The builder needs it too: for a viewer with
  # `form_submissions.view` alone a form opens on its submissions, which
  # Task 5 builds (until then it is the 403). A trashed form is not found
  # here: it is the Trash screen's.
  #
  # SAVING is explicit, through the save bar (configuration screens save
  # explicitly, docs/reference/save-rule-and-write-queue.md), with the
  # stale-save rule of `Admin::StaleForm`: a Save whose base is older than
  # the form is the 409 with what was typed still in the form, before
  # `Forms::Save` is called, so nothing is written. The base is the form's
  # `updated_at`, which moves with every save that changes anything the
  # builder shows: `Forms::Save` writes the row, and touches it when only
  # the destinations changed or a secret was written (moving no content
  # version then), so a Save from an older copy can't put old destinations
  # back.
  class FormsController < BaseController
    include StaleForm

    PER_PAGE = 50

    before_action -> { forbidden! unless holds_any?(%w[forms.manage form_submissions.view]) }, only: :index
    before_action -> { require_permission("forms.manage") }, except: :index
    before_action :set_form, only: %i[show update destroy]

    def index
      relation = Forms::Form.kept.order(:name, :id)
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: relation.count)
      @forms = @pagination.out_of_range? ? [] : relation.offset(@pagination.offset).limit(PER_PAGE).to_a
    end

    def new
      @dialog = new_dialog
    end

    # New form (design.md 1): a name, a start ("contact": three required
    # fields; "blank": none) and the recipients of its mail, prefilled with
    # the person's own address. With no recipient the form keeps its
    # submissions instead, where the site can (`Forms::Save` refuses a form
    # with nowhere to send, and keeping without keys, with its sentences).
    def create
      posted = new_form_params
      recipients = posted[:recipients].to_s
      keep = recipients.strip.empty? && Forms::Encryption.available?
      result = Forms::Save.call(Forms::Form.new, attributes: { name: posted[:name], keep_submissions: keep },
        fields: starter_fields(posted[:start]),
        destinations: recipients.strip.empty? ? [] : [ { kind: Admin::FormsScreen::DestinationsComponent::MAIL, settings: { recipients: recipients }, secrets: {} } ])

      if result.ok?
        redirect_to admin_form_path(result.record, **admin_url_options), status: :see_other, notice: t(".created")
      else
        forbidden_or(result) do
          @dialog = new_dialog(name: posted[:name], start: posted[:start], recipients: recipients, errors: result.errors)
          if params[:from] == "page"
            render :new, status: :unprocessable_entity
          else
            index
            render :index, status: :unprocessable_entity
          end
        end
      end
    end

    def show
      @draft = Admin::FormsScreen::Draft.from_form(@form)
    end

    def update
      posted = params[:form]
      default_tab = posted.respond_to?(:key?) && posted[:tab].to_s.presence_in([ Locales.default ]).present?
      @draft = Admin::FormsScreen::Draft.from_params(@form, posted, default_tab: default_tab)
      return render_stale(:show, @form) if stale_form?(@form, params[:base_updated_at])

      arguments = @draft.save_arguments(secrets: default_tab ? Admin::FormsScreen::Draft.posted_secrets(posted) : {})
      result = Forms::Save.call(@form, **arguments)

      if result.ok?
        redirect_to admin_form_path(@form, **admin_url_options), status: :see_other, notice: t(".saved")
      else
        forbidden_or(result) do
          @errors = result.errors
          render :show, status: :unprocessable_entity
        end
      end
    end

    def destroy
      name = @form.name
      result = Trash::Move.call(@form)

      if result.ok?
        flash[:undo] = { "label" => t(".undo"), "url" => admin_restore_trash_item_path("form", @form, from: "undo", **admin_url_options) }
        redirect_to admin_forms_path(**admin_url_options), status: :see_other, notice: t(".moved", name: name)
      else
        forbidden_or(result) { redirect_to admin_form_path(@form, **admin_url_options), status: :see_other, alert: result.errors.to_sentence } # i18n-ok: to_sentence joins with the locale's support.array words
      end
    end

    private

    # A kept form; a trashed or missing one is the 404.
    def set_form
      @form = Forms::Form.kept.find(params[:id])
    end

    def new_form_params
      posted = params[:form]
      posted.respond_to?(:permit) ? posted.permit(:name, :start, :recipients) : ActionController::Parameters.new.permit
    end

    def new_dialog(**values)
      Admin::FormsScreen::NewFormDialogComponent.new(**values, page: action_name.in?(%w[new]) || params[:from] == "page", url_options: admin_url_options)
    end

    # The starter's three fields (design.md 1), labelled in the default
    # language with CS Studio's words; "blank" is none. Each type is the
    # registered one whose value is of that kind (a line, an address, a
    # text), so nothing here names a form field type.
    STARTER = { name: :string, email: :email, message: :text }.freeze

    def starter_fields(start)
      return [] if start.to_s == "blank"

      STARTER.filter_map do |key, value_type|
        type = Forms::FieldTypes.all.find { |candidate| candidate.value_type == value_type }
        next unless type

        { type: type.name, required: true, label: { Locales.default => t("admin.components.forms_screen.new_form_dialog.starter.#{key}") }, help: {} }
      end
    end
  end
end
