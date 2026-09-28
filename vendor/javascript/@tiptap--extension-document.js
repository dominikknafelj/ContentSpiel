// @tiptap/extension-document@3.31.3 downloaded from https://ga.jspm.io/npm:@tiptap/extension-document@3.31.3/dist/index.js

import{Node as e}from"@tiptap/core";const t=e.create({name:`doc`,topNode:!0,content:`block+`,renderMarkdown:(e,t)=>e.content?t.renderChildren(e.content,`

`):``});var n=t;export{t as Document,n as default};

