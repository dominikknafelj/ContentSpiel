// What the mind graph's layout is tuned by, beside d3's own figures in
// `layout_worker.js` (pages in the mind graph, spec §5). Kept on the page's
// side and handed to the worker with `start` (`layout_client.js` sends them
// with every one), so that they are values a test can read, and lower: a
// test of the worker gives it springs and an ease of its own instead of
// waiting out the real ones.
//
// SPRINGS: a line's spring by its kind, its length at rest and how hard it
// pulls. A kind that is not named has d3's own (a rest length of 90, and a
// strength that falls with the number of lines at its ends). A tree line is
// SHORT AND STIFF, so a subtree stays together; these are the spec's
// starting values, tuned at the measurement (pages plan, Task 9).
export const SPRINGS = { tree: { distance: 40, strength: 0.9 } }

// EASE: how a released anchor travels back to the centre. `keep` is how much
// of its way it has left after each tick, `within` how near (in graph
// units) counts as there. From 500 units away that is some forty ticks, two
// thirds of a second at frame pace; the layout the release warmed up takes
// about 250 to cool down, so the ease always ends first.
export const EASE = { keep: 0.85, within: 0.5 }
