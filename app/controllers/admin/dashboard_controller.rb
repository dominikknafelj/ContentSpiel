module Admin
  # CS Studio's start page (dashboard spec §3-§4, design pass round 2): quick
  # create, the cards "Your drafts", "Going live next" and "Needs
  # translation", and "Recent activity". Open to every signed-in user -- its own
  # `MODULES` entry (`BaseController::MODULES`) has `permission: nil`, so a
  # user whose groups hold no grants at all (nothing to read, nothing to
  # write) still lands here instead of a 403 the moment they sign in; each
  # list it shows is read-scoped (`Dashboard::Feed`, through
  # `AccessControl.scope`), so it simply comes back empty for them, the
  # same way every other admin list already does, and quick create shows
  # only what they can do (`Admin::DashboardScreen::QuickCreateComponent`).
  class DashboardController < BaseController
    def show
      load_dashboard
    end

    # Quick draft (dashboard spec §4.1): a title and a content type, saved
    # through `Posts::Save` as an unpublished post -- the title in the
    # site's default language, whatever language is being edited, since a
    # quick draft is the start of a post, not a translation of one -- and
    # opened in the editor. `Posts::Save` authorizes `posts.create` against
    # the post *with* its content type, so a type the select never offered
    # (a forged param) is refused there: a 403 via `forbidden_or`, like
    # every other admin write. Anything else (a blank title, an unknown
    # type) re-renders the dashboard with the errors inline, 422.
    def create_draft
      # "Page" in the quick-create select (the bar's JS opens the New page
      # dialog instead; this is the no-JS path): nothing is created here --
      # the standalone New page screen takes over and asks `pages.create`.
      return redirect_to(new_admin_page_path(**admin_url_options), status: :see_other) if params[:content_type] == Admin::DashboardScreen::QuickCreateComponent::PAGE

      result = Posts::Save.call(attributes: { content_type: params[:content_type].to_s, published: false },
        translations: { Locales.default => { title: params[:title].to_s } })

      if result.ok?
        redirect_to admin_post_path(result.record, **admin_url_options), notice: "Draft created", status: :see_other
      else
        forbidden_or(result) do
          load_dashboard
          @draft = { title: params[:title].to_s, content_type: params[:content_type].to_s, errors: result.errors }
          render :show, status: :unprocessable_entity
        end
      end
    end

    private

    # Everything the page shows, each part read-scoped for the viewer
    # (`Dashboard::Feed`, `Activity`, `TranslationNeeds`) and loaded in a
    # constant number of queries.
    def load_dashboard
      # Only a holder of settings.manage can fix mail, so only they are told
      # (spec "The states"; the notice draws itself only while the last send failed).
      @mail_settings = MailSettings.current if can?("settings.manage")
      @feed = Dashboard::Feed.new(actor: Current.actor)
      @activity = Dashboard::Activity.new(actor: Current.actor)
      @translation_needs = Dashboard::TranslationNeeds.new(actor: Current.actor)
    end
  end
end
