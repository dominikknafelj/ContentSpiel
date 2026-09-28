require "test_helper"

# Ports the real invariants the deleted admin's own integration tests used
# to exercise (task 10 brief, spec §6.2) into tests against CS Studio,
# models and services directly, rather than the old admin's own URLs -- its
# request/response shape (its resource forms, its tabs, its association
# panels) is gone along with it, so what's ported here is the underlying
# rule each old test was really guarding, not its HTTP mechanics.
#
# Several of the six invariants the brief names were already fully ported
# by earlier tasks (CS Studio's own build), so they're cross-referenced
# below rather than duplicated:
#   - "the last user can't be deleted" -- User#ensure_not_last_owner
#     (test/models/user_test.rb "the last user can't be destroyed"),
#     Users::Destroy (test/services/users/destroy_test.rb "refuses to
#     delete the last user") and the CS Studio screen itself
#     (test/integration/admin/users_test.rb "refuses to delete the last
#     user").
#   - "the site settings singleton" -- SiteSetting's own uniqueness
#     validation (test/models/site_setting_test.rb "a second record cannot
#     be created") and the settings screen's own form
#     (test/integration/admin/settings_test.rb). The one other assertion the
#     old settings test made -- an index route redirecting straight to
#     edit -- was routing specific to the deleted admin's own generic
#     resource machinery, not a real invariant: CS Studio's `resource
#     :settings` has no index to redirect from at all.
#   - "the mind graph data" -- PostGraph's own node/edge query
#     (test/queries/post_graph_test.rb) and the CS Studio screen
#     (test/integration/admin/mind_graph_test.rb: colours, editor urls,
#     edges, the data-island XSS guard and the empty state).
#   - "page reorder semantics" -- already covered directly by
#     test/services/pages/move_test.rb (Pages::Move) and at the integration
#     level by test/integration/admin/tree_test.rb.
#
# The rest of the deleted admin's own test suite exercised its own generic
# resource machinery (nested attributes wiring, per-locale tabs, typed-fields
# rendering) rather than an invariant belonging to this app -- CS Studio has
# its own hand-built forms for all of it, independently tested in
# test/integration/admin/page_editor_test.rb, page_creation_test.rb,
# content_blocks_test.rb and posts_test.rb (typed fields, translated fields,
# hero image, related posts, tags, etc.). Nothing from those files needed
# porting here.
class Admin::InvariantsTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # The deleted admin's own ApiToken resource had to turn away both a New
  # form and a direct create, since ApiToken has no usable New form (the
  # digest is never hand-entered). CS Studio's route list has no :new at all
  # (config/routes.rb: `resources :api_tokens, only: %i[index create
  # destroy]`), and `create` never reads a submitted `api_token` param -- it
  # calls `ApiTokens::Issue.call(Current.user)` verbatim
  # (app/controllers/admin/api_tokens_controller.rb). Proven here against
  # the real route, not just by reading the controller: whatever a request
  # smuggles in, the minted token belongs to whoever is signed in, never a
  # submitted user_id or digest, and another user's own tokens are left
  # alone.
  test "tokens are only minted through ApiTokens::Issue -- no route lets a request set the user or digest" do
    sign_in_as(users(:one))
    other_token, other_raw = ApiTokens::Issue.call(users(:two)).record

    assert_difference -> { ApiToken.count }, 1 do
      post "/cs-studio/api_tokens", params: {
        api_token: { user_id: users(:two).id, token_digest: "hand-typed", revoked_at: "" }
      }
    end

    assert_response :success
    token = ApiToken.order(:id).last
    assert_equal users(:one), token.user, "a token must always belong to whoever created it, never a submitted user_id"
    assert_not_equal "hand-typed", token.token_digest

    assert_nil other_token.reload.revoked_at, "issuing a token for one user must not touch another user's tokens"
    assert_equal other_token, ApiToken.authenticate(other_raw)
  end

  # The old admin's own gating tests hit its own mount point; CS Studio
  # itself, not just the admin that came before it, is gated behind setup
  # the same way -- Setup::RedirectConstraint's own comment already says it
  # covers CS Studio, but nothing exercised that directly until now.
  test "CS Studio is gated behind /setup while setup is required" do
    start_fresh_install

    [ "/cs-studio", "/cs-studio/posts", "/cs-studio/settings" ].each do |path|
      get path
      assert_redirected_to "/setup", "expected #{path} to redirect to /setup"
    end
  end

  # The old admin's own mount point is gone outright now, not just
  # re-pointed -- a request for it must 404, the same as any other unmounted
  # path, rather than silently resolving to something else in CS Studio's
  # own route space.
  test "the old admin's mount point no longer exists" do
    sign_in_as(users(:one))

    get "/avo"
    assert_response :not_found

    get "/avo/resources/posts"
    assert_response :not_found
  end
end
