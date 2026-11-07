// The pieces of CS Studio the card and the list put on screen, cloned from
// the server's own markup: `Admin::MindGraphScreen::PartsComponent` renders
// each shared component (the status chips, the unpublished chip, an icon
// chip per kind, the card's Close) once into `template[data-mind-graph-parts]`
// inside the graph's element, one `span[data-part=<name>]` around each. So
// no chip and no button is drawn by hand here, and a component's change
// reaches the graph with it.
//
// `readParts(element)` answers `{ part(name) }`: each call a deep clone of
// that part's one element, in no document, for the caller to put where it
// goes. A clone is never changed after it is made: whatever a caller has to
// say beside it (a two-state name, `aria-hidden`) goes on the element it is
// put into. A name the template does not hold, or a page without the
// template, throws: a part that is missing is a broken page, as loud as an
// import that failed, never a card drawn without its chip.
export function readParts(element) {
  const template = element.querySelector("template[data-mind-graph-parts]")

  return {
    part(name) {
      const held = Array.from(template?.content.children ?? []).find((span) => span.dataset.part === name)?.firstElementChild
      if (!held) throw new Error(`mind graph: no part named ${name}`)
      return held.cloneNode(true)
    }
  }
}
