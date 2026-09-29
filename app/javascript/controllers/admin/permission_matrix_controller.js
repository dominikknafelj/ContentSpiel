import { Controller } from "@hotwired/stimulus"

// The group editor's permission matrix (`Admin::PermissionMatrixComponent`):
// ticking a scoped permission reveals its scope controls, unticking hides
// them again. Only visibility -- the controls stay in the form either way,
// and `Admin::GroupsController#grants_from` ignores the scope of a
// permission that isn't ticked, so a hidden control never grants anything.
export default class extends Controller {
  static targets = ["scope"]

  toggle(event) {
    const row = event.target.closest("[data-permission]")
    const scope = this.scopeTargets.find((target) => row?.contains(target))
    if (scope) scope.hidden = !event.target.checked
  }
}
