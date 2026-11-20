# rod.001: `Element#select_all_text` does not select `<input>` text

**Shard:** rod (`dsisnero/rod`)
**Pinned commit:** `46e6c7fc344531fe395dd964fd13c64084b5753c`
**Upstream reference:** go-rod `v0.116.2`, vendored by rodney `v0.4.0`
**Priority:** Medium
**Type:** parity bug (silent data corruption in a user-facing command)

## Summary

`Rod::Element#select_all_text` selects a **document** range. Document ranges do
not cover `<input>` / `<textarea>` contents, so nothing is selected in a form
field and the follow-up `InsertText` lands at the caret. Go rod selects the
**field** range with `this.select()`, so `MustSelectAllText().MustInput(text)`
replaces the value.

The shard already contains the Go helper verbatim; it simply is not called from
this method.

## Code comparison

Go rod — `element.go:243-254`:

```go
func (el *Element) SelectAllText() error {
	if err := el.Focus(); err != nil {
		return err
	}
	defer el.tryTrace(TraceTypeInput, "select all text")()
	el.page.browser.trySlowMotion()
	_, err := el.Evaluate(evalHelper(js.SelectAllText).ByUser())
	return err
}
```

Go rod — `lib/js/helper.go:152-156`:

```go
var SelectAllText = &Function{
	Name:         "selectAllText",
	Definition:   `function(){this.select()}`,
	Dependencies: []*Function{},
}
```

rod Crystal — `src/rod/element.cr` (the diverging method):

```crystal
def select_all_text : Nil
  cleanup = try_trace(Rod::TraceTypeInput, "select all text")
  @page.browser.try_slow_motion

  begin
    focus
    evaluate("() => {
        const sel = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(this);
        sel.removeAllRanges();
        sel.addRange(range);
    }")
  ensure
    cleanup.call
  end
end
```

rod Crystal already ships the Go helper — `src/rod/util/js.cr:86-90`:

```crystal
SELECT_ALL_TEXT = Function.new(
  name: "selectAllText",
  definition: "function(){this.select()}",
  dependencies: [] of Function
)
```

## Why the range approach fails

`window.getSelection()` returns the selection associated with the document's
rendering tree. HTML inputs and textareas keep their selection in
`selectionStart` / `selectionEnd` and are **not** exposed through
`window.getSelection()`. `range.selectNodeContents(this)` on an `<input>` has
no visible target, so the call succeeds while selecting nothing.

Consequence for `InsertText`: with no selection the caret sits where focus last
had it (start of the field on first focus), so the new text is prepended and the
old value is preserved.

`this.select()` is the DOM API that selects a field's contents, and it is
exactly what Go rod evaluates.

## Impact in webb

Upstream `cmdInput` / `cmdClear` (`vendor/rodney/main.go:771-798`) both call
`el.MustSelectAllText().MustInput(...)`, and Crystal's `Element#input` only
replaces text when something is selected first:

| command | expected | actual |
| --- | --- | --- |
| `webb input "#search-form input" "hello there"` on `value="hi"` | `hello there` | `hello therehi` |
| `webb clear "#search-form input"` | `` (empty) | unchanged value |

`webb clear` therefore cannot empty a field at all.

## Reproduction

The CLI fixture page (`spec/cli_spec.cr`) renders:

```html
<form id="search-form" action="/submitted"><input name="q" value="hi"></form>
```

```bash
webb open "http://127.0.0.1:PORT/"
webb input "#search-form input" "hello there"
webb js "document.querySelector('#search-form input').value"
# prints: hello therehi
```

Go rod leaves `hello there` for the same sequence.

## Cause confirmed

Running Go's helper body through the CLI before the same `input` call:

```bash
webb js "document.querySelector('#search-form input').select()"
webb input "#search-form input" "hello there"
webb js "document.querySelector('#search-form input').value"
# prints: hello there
```

So the divergence is the selection step, not `InsertText`, and the shard's own
`SELECT_ALL_TEXT` helper is the fix.

## Fix sketch

```diff
 def select_all_text : Nil
   cleanup = try_trace(Rod::TraceTypeInput, "select all text")
   @page.browser.try_slow_motion

   begin
     focus
-    evaluate("() => {
-        const sel = window.getSelection();
-        const range = document.createRange();
-        range.selectNodeContents(this);
-        sel.removeAllRanges();
-        sel.addRange(range);
-    }")
+    evaluate(eval_helper(Rod::JS::SELECT_ALL_TEXT))
   ensure
     cleanup.call
   end
 end
```

Go also marks the evaluation with `.ByUser()` (a user-gesture flag). Mirror it
if `EvalOptions` exposes the equivalent, so `this.select()` runs in the same
gesture context Chrome sees for real input.

## Spec to add in the shard

`spec/element_select_all_text_parity_spec.cr` (rod's specs run a real Chrome):

```crystal
it "replaces a text field's value like go-rod's SelectAllText" do
  page = ... # open a data: URL with <input value="hi">
  el = page.element("input")
  el.select_all_text
  el.input("hello there")
  page.eval("() => document.querySelector('input').value")
    .value.to_s.should eq("hello there")
end
```

The same example fails on the current implementation with `hello therehi`,
which is the failing-before proof the shard patch flow requires.

## Landing sequencing

The fork's `main` (`71c0134`) is **14 commits ahead** of this repo's lock
(`46e6c7f`), and several of those change element-lookup errors and wait
behaviour (`port: report lookup misses as ElementNotFoundError`,
`port: inherit context deadlines like go's context.WithTimeout`,
`port: retry Element.Wait* through the page sleeper like go-rod`). Those
messages are pinned by webb specs such as
`error: element not found: context deadline exceeded`.

So do **not** `shards update rod` and take whatever `main` holds. Cut the fix
branch from `46e6c7f`, prove it with the shard spec above, then move
`shard.lock` deliberately — either to that branch commit (minimal delta) or to
`main` once the fork's newer work is separately reviewed for webb.

## Post-fix checklist for webb

1. Un-`pending` `spec/cli_spec.cr` → "replaces the field value like
   MustSelectAllText".
2. Flip `cmdInput` and `cmdClear` to `ported` in
   `plans/inventory/go_port_inventory.tsv` and drop the blocker note.
3. Remove the open-gap sentence in `plans/parity.md` → *Intentional
   divergences*.
4. Re-run `make test` and `make inventory`; the shard pin change is one commit.

## Related

- Go rod `Element.SelectAllText`: `element.go:243-254`
- Go rod `js.SelectAllText`: `lib/js/helper.go:152-156`
- rod Crystal `src/rod/element.cr` (`select_all_text`), `src/rod/util/js.cr`
- Upstream go-rod does not have a spec for `SelectAllText`; the shard spec above
  is the missing coverage.
