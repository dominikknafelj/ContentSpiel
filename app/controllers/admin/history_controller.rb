module Admin
  # A page's or a post's History screen (version history spec §3, R4, R14,
  # R15): its published versions newest first, under the working version, and
  # the comparison of one version with another or with the working version,
  # in one language.
  #
  # SEEING A HISTORY NEEDS `<kind>s.edit` ON THE RECORD, the plain key and not
  # the owner rule (R4): an Author sees the history of their own live post.
  # The record is found through that scope, so a record outside it, a trashed
  # one and one without the key alike are not found (404), never forbidden.
  # Restoring is asked separately (`@may_restore`): what editing the record
  # needs (`AccessControl::OwnerRule`), as a discard asks, and a post of a
  # switched-off type takes no write at all.
  #
  # Every choice is the GET's query: `version` (the newest copy when absent),
  # `with` (`previous`, the default, which is the working version for the
  # first copy; `working`; or another copy's number), `locale` (the admin's
  # own language parameter, so the editor linked from here opens in it) and
  # `page` (the versions' page). A number that names no copy is a 404.
  #
  # THE COMPARISON READS FORWARD IN TIME: the older side is `from`, so a
  # version with the one before it shows what that publish changed, and a
  # version with the working version what has been saved since it.
  class HistoryController < BaseController
    KINDS = { "page" => ::Page, "post" => ::Post }.freeze

    before_action :set_record

    def show
      @history = ::Publishing::History.new(@record, page: params[:page])
      @version = chosen_version
      return unless @version

      @previous = @history.previous(@version.number)
      @with = with_choice
      other = compared_with
      from, to = other == :working || other.number > @version.number ? [ @version, other ] : [ other, @version ]
      @changes = ::Publishing::Changes.between(@record, from: from, to: to)
      @may_restore = may_restore?
      @restore_offered = @may_restore && !(other == :working ? @changes : ::Publishing::Changes.between(@record, from: @version, to: :working)).none?
    end

    private

    def kind = params[:kind]

    def set_record
      model = KINDS.fetch(kind) { raise ActiveRecord::RecordNotFound }
      @record = admin_scope(model.all, "#{kind}s.edit").find(params[:id])
    end

    def chosen_version
      return @history.newest if params[:version].blank?

      @history.find(number_param(:version))
    end

    # What the `with` select shows chosen: "previous" while a copy comes
    # before this one, "working" for the first copy or on asking, or a number.
    def with_choice
      case params[:with].to_s
      when "working" then "working"
      when "", "previous" then @previous ? "previous" : "working"
      else number_param(:with).to_s
      end
    end

    def compared_with
      case @with
      when "working" then :working
      when "previous" then @previous
      else @history.find(@with.to_i)
      end
    end

    # A number that is no whole number names no copy.
    def number_param(name) = Integer(params[name].to_s, 10, exception: false) || raise(ActiveRecord::RecordNotFound)

    def may_restore?
      return false if @record.is_a?(::Post) && !@record.type_switched_on?

      AccessControl::OwnerRule.refusal(@record) { |key| can?(key, @record) }.nil?
    end
  end
end
