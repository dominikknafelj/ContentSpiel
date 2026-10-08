require "application_system_test_case"

# The mind graph's own modules (`app/javascript/mind_graph/`), imported in the
# browser from any CS Studio page: the project has no JavaScript test runner,
# and these are plain modules the import map resolves, so a system test can
# call them directly and compare what they return.
class Admin::MindGraphModulesSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    visit admin_tags_path
    await_admin_controllers
  end

  test "the layout worker starts from its asset URL, lays three nodes out and settles" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"), ActionController::Base.helpers.asset_path("d3-force.js"))
      const [workerUrl, d3Url, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        let ticks = 0
        let last = null
        const layout = createLayout({
          workerUrl, d3Url,
          onTick: (positions) => { ticks += 1; last = Array.from(positions) },
          onSettled: () => { layout.stop(); done({ ticks, last }) },
          onError: (message) => done({ error: message })
        })
        layout.start([{ id: 1, radius: 8 }, { id: 2, radius: 8 }, { id: "tag-3", radius: 6 }], [{ source: 1, target: 2 }, { source: 2, target: "tag-3" }])
      })
    JS

    assert_nil result["error"]
    assert_operator result["ticks"], :>, 0
    assert_equal 6, result["last"].size
    assert result["last"].all? { |value| value.is_a?(Numeric) && value.finite? }
    xs = result["last"].each_slice(2).map(&:first)
    assert_equal 3, xs.uniq.size, "three nodes at one x: the simulation never ran"
  end

  test "a worker that can't load d3-force reports an error instead of hanging" do
    result = page.evaluate_async_script(<<~JS, ActionController::Base.helpers.asset_path("mind_graph/layout_worker.js"))
      const [workerUrl, done] = arguments
      import("mind_graph/layout_client").then(({ createLayout }) => {
        const layout = createLayout({
          workerUrl, d3Url: "/assets/no-such-file.js",
          onTick: () => {}, onSettled: () => done({ settled: true }),
          onError: (message) => { layout.stop(); done({ error: message }) }
        })
        layout.start([{ id: 1, radius: 8 }], [])
      })
    JS

    assert result["error"].present?
  end
end
